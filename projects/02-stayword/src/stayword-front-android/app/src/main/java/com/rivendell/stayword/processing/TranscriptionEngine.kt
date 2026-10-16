package com.rivendell.stayword.processing

import com.k2fsa.sherpa.onnx.FastClusteringConfig
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineSenseVoiceModelConfig
import com.k2fsa.sherpa.onnx.OfflineSpeakerDiarization
import com.k2fsa.sherpa.onnx.OfflineSpeakerDiarizationConfig
import com.k2fsa.sherpa.onnx.OfflineSpeakerSegmentationModelConfig
import com.k2fsa.sherpa.onnx.OfflineSpeakerSegmentationPyannoteModelConfig
import com.k2fsa.sherpa.onnx.SileroVadModelConfig
import com.k2fsa.sherpa.onnx.SpeakerEmbeddingExtractorConfig
import com.k2fsa.sherpa.onnx.Vad
import com.k2fsa.sherpa.onnx.VadModelConfig
import com.rivendell.stayword.domain.ProcessingState
import com.rivendell.stayword.domain.TranscriptDraft
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.coroutineContext
import kotlin.math.ceil
import kotlin.math.floor

interface TranscriptionEngine {
    suspend fun transcribe(
        preparedAudio: PreparedAudio,
        modelRoot: File,
        onStage: suspend (ProcessingState, Float) -> Unit,
    ): List<TranscriptDraft>
}

class SherpaTranscriptionEngine : TranscriptionEngine {
    override suspend fun transcribe(
        preparedAudio: PreparedAudio,
        modelRoot: File,
        onStage: suspend (ProcessingState, Float) -> Unit,
    ): List<TranscriptDraft> = withContext(Dispatchers.Default) {
        require(preparedAudio.sampleRate == SAMPLE_RATE)
        val samples = preparedAudio.samples
        require(samples.isNotEmpty()) { "Audio contains no samples" }

        onStage(ProcessingState.VAD, 0.12f)
        val speech = detectSpeech(samples, modelRoot)
        require(speech.isNotEmpty()) { "No speech was detected" }
        coroutineContext.ensureActive()

        onStage(ProcessingState.DIARIZING, 0.28f)
        val turns = diarize(samples, modelRoot)
        coroutineContext.ensureActive()

        onStage(ProcessingState.ALIGNING, 0.48f)
        val units = TranscriptionSegmentPlanner.makeUnits(
            speech,
            turns,
            samples.size.toDouble() / SAMPLE_RATE,
        )
        require(units.isNotEmpty()) { "No transcript segments could be aligned" }

        onStage(ProcessingState.TRANSCRIBING, 0.55f)
        transcribeUnits(samples, units, modelRoot) { completed, total ->
            onStage(
                ProcessingState.TRANSCRIBING,
                0.55f + 0.25f * (completed.toFloat() / total.coerceAtLeast(1)),
            )
        }
    }

    private fun detectSpeech(samples: FloatArray, root: File): List<SpeechInterval> {
        val config = VadModelConfig(
            sileroVadModelConfig = SileroVadModelConfig(
                model = File(root, "vad/silero_vad.onnx").absolutePath,
                threshold = 0.5f,
                minSilenceDuration = 0.35f,
                minSpeechDuration = 0.2f,
                windowSize = VAD_WINDOW_SIZE,
                maxSpeechDuration = 30f,
            ),
            sampleRate = SAMPLE_RATE,
            numThreads = THREADS,
            provider = "cpu",
            debug = false,
        )
        val vad = Vad(config = config)
        return try {
            val intervals = mutableListOf<SpeechInterval>()
            var offset = 0
            while (offset + VAD_WINDOW_SIZE <= samples.size) {
                vad.acceptWaveform(samples.copyOfRange(offset, offset + VAD_WINDOW_SIZE))
                drainVad(vad, intervals, samples.size)
                offset += VAD_WINDOW_SIZE
            }
            if (offset < samples.size) {
                val finalWindow = FloatArray(VAD_WINDOW_SIZE)
                samples.copyInto(finalWindow, endIndex = samples.size, startIndex = offset)
                vad.acceptWaveform(finalWindow)
                drainVad(vad, intervals, samples.size)
            }
            vad.flush()
            drainVad(vad, intervals, samples.size)
            mergeIntervals(intervals)
        } finally {
            vad.release()
        }
    }

    private fun drainVad(vad: Vad, intervals: MutableList<SpeechInterval>, sampleCount: Int) {
        while (!vad.empty()) {
            val segment = vad.front()
            val start = segment.start.coerceAtLeast(0).coerceAtMost(sampleCount)
            val end = (start + segment.samples.size).coerceAtMost(sampleCount)
            if (end > start) intervals += SpeechInterval(start.toDouble() / SAMPLE_RATE, end.toDouble() / SAMPLE_RATE)
            vad.pop()
        }
    }

    private fun mergeIntervals(intervals: List<SpeechInterval>): List<SpeechInterval> {
        val result = mutableListOf<SpeechInterval>()
        intervals.sortedWith(compareBy<SpeechInterval> { it.startSeconds }.thenBy { it.endSeconds })
            .forEach { interval ->
                val previous = result.lastOrNull()
                if (previous != null && interval.startSeconds <= previous.endSeconds) {
                    result[result.lastIndex] = previous.copy(endSeconds = maxOf(previous.endSeconds, interval.endSeconds))
                } else {
                    result += interval
                }
            }
        return result
    }

    private fun diarize(samples: FloatArray, root: File): List<SpeakerTurn> {
        val config = OfflineSpeakerDiarizationConfig(
            segmentation = OfflineSpeakerSegmentationModelConfig(
                pyannote = OfflineSpeakerSegmentationPyannoteModelConfig(
                    model = File(root, "pyannote/model.int8.onnx").absolutePath,
                ),
                numThreads = THREADS,
                debug = false,
                provider = "cpu",
            ),
            embedding = SpeakerEmbeddingExtractorConfig(
                model = File(root, "speaker/3dspeaker.onnx").absolutePath,
                numThreads = THREADS,
                debug = false,
                provider = "cpu",
            ),
            clustering = FastClusteringConfig(numClusters = -1, threshold = 0.8f),
            minDurationOn = 0.2f,
            minDurationOff = 0.5f,
        )
        val diarizer = OfflineSpeakerDiarization(config = config)
        return try {
            check(diarizer.sampleRate() == SAMPLE_RATE) { "Speaker model sample rate mismatch" }
            diarizer.process(samples)
                .filter { it.start.isFinite() && it.end.isFinite() && it.start >= 0f && it.end > it.start }
                .map { SpeakerTurn(it.start.toDouble(), it.end.toDouble(), it.speaker) }
        } finally {
            diarizer.release()
        }
    }

    private suspend fun transcribeUnits(
        samples: FloatArray,
        units: List<TranscriptionUnit>,
        root: File,
        onProgress: suspend (Int, Int) -> Unit,
    ): List<TranscriptDraft> {
        val modelConfig = OfflineModelConfig(
            senseVoice = OfflineSenseVoiceModelConfig(
                model = File(root, "sensevoice/model.int8.onnx").absolutePath,
                language = "auto",
                useInverseTextNormalization = true,
            ),
            numThreads = THREADS,
            debug = false,
            provider = "cpu",
            modelType = "sense_voice",
            tokens = File(root, "sensevoice/tokens.txt").absolutePath,
        )
        val config = OfflineRecognizerConfig(
            featConfig = FeatureConfig(sampleRate = SAMPLE_RATE, featureDim = 80),
            modelConfig = modelConfig,
            decodingMethod = "greedy_search",
            maxActivePaths = 4,
        )
        val recognizer = OfflineRecognizer(config = config)
        return try {
            buildList {
                units.forEachIndexed { index, unit ->
                    coroutineContext.ensureActive()
                    val lower = floor(unit.startSeconds * SAMPLE_RATE).toInt().coerceIn(0, samples.size)
                    val upper = ceil(unit.endSeconds * SAMPLE_RATE).toInt().coerceIn(0, samples.size)
                    if (lower < upper) {
                        val stream = recognizer.createStream()
                        val text = try {
                            stream.acceptWaveform(samples.copyOfRange(lower, upper), SAMPLE_RATE)
                            recognizer.decode(stream)
                            cleanSenseVoiceText(recognizer.getResult(stream).text)
                        } finally {
                            stream.release()
                        }
                        if (text.isNotBlank()) {
                            add(
                                TranscriptDraft(
                                    startMs = (unit.startSeconds * 1_000).toLong(),
                                    durationMs = ((unit.endSeconds - unit.startSeconds) * 1_000).toLong(),
                                    text = text,
                                    speakerIndex = unit.speaker,
                                ),
                            )
                        }
                    }
                    onProgress(index + 1, units.size)
                }
            }.also { require(it.isNotEmpty()) { "Speech recognition produced an empty transcript" } }
        } finally {
            recognizer.release()
        }
    }

    private fun cleanSenseVoiceText(raw: String): String = raw
        .replace(Regex("<\\|.*?\\|>"), "")
        .trim()
        .replace(Regex("\\s+"), " ")

    private companion object {
        const val SAMPLE_RATE = 16_000
        const val THREADS = 2
        const val VAD_WINDOW_SIZE = 512
    }
}
