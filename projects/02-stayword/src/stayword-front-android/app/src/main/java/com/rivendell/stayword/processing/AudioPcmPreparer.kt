package com.rivendell.stayword.processing

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteOrder
import kotlin.coroutines.coroutineContext
import kotlin.math.ceil
import kotlin.math.floor

data class PreparedAudio(
    val samples: FloatArray,
    val sampleRate: Int = 16_000,
) {
    val durationMs: Long
        get() = samples.size * 1_000L / sampleRate
}

interface AudioPcmPreparer {
    suspend fun prepare(file: File): PreparedAudio
}

class MediaCodecAudioPcmPreparer : AudioPcmPreparer {
    override suspend fun prepare(file: File): PreparedAudio = withContext(Dispatchers.IO) {
        require(file.isFile && file.canRead()) { "Audio file is unavailable" }
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(file.absolutePath)
            val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("No audio track found")
            extractor.selectTrack(trackIndex)
            val inputFormat = extractor.getTrackFormat(trackIndex)
            val mime = requireNotNull(inputFormat.getString(MediaFormat.KEY_MIME))
            codec = MediaCodec.createDecoderByType(mime).apply {
                configure(inputFormat, null, null, 0)
                start()
            }

            var sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT
            val output = FloatAccumulator()
            val bufferInfo = MediaCodec.BufferInfo()
            var inputEnded = false
            var outputEnded = false

            while (!outputEnded) {
                coroutineContext.ensureActive()
                if (!inputEnded) {
                    val inputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val inputBuffer = requireNotNull(codec.getInputBuffer(inputIndex)).apply { clear() }
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputEnded = true
                        } else {
                            codec.queueInputBuffer(inputIndex, 0, sampleSize, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                when (val outputIndex = codec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val format = codec.outputFormat
                        sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            pcmEncoding = format.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        }
                    }

                    MediaCodec.INFO_TRY_AGAIN_LATER -> Unit

                    else -> if (outputIndex >= 0) {
                        codec.getOutputBuffer(outputIndex)?.let { buffer ->
                            if (bufferInfo.size > 0) {
                                buffer.position(bufferInfo.offset)
                                buffer.limit(bufferInfo.offset + bufferInfo.size)
                                buffer.order(ByteOrder.nativeOrder())
                                appendPcm(buffer, channelCount, pcmEncoding, output)
                            }
                        }
                        outputEnded = bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        codec.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }

            val mono = output.toArray()
            require(mono.isNotEmpty()) { "Decoded audio is empty" }
            PreparedAudio(samples = resampleLinear(mono, sampleRate, TARGET_SAMPLE_RATE))
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            extractor.release()
        }
    }

    private fun appendPcm(
        buffer: java.nio.ByteBuffer,
        channelCount: Int,
        pcmEncoding: Int,
        output: FloatAccumulator,
    ) {
        val channels = channelCount.coerceAtLeast(1)
        when (pcmEncoding) {
            AudioFormat.ENCODING_PCM_FLOAT -> {
                val floats = buffer.asFloatBuffer()
                while (floats.remaining() >= channels) {
                    var sum = 0f
                    repeat(channels) { sum += floats.get() }
                    output.add((sum / channels).coerceIn(-1f, 1f))
                }
            }

            else -> {
                val shorts = buffer.asShortBuffer()
                while (shorts.remaining() >= channels) {
                    var sum = 0f
                    repeat(channels) { sum += shorts.get() / 32768f }
                    output.add((sum / channels).coerceIn(-1f, 1f))
                }
            }
        }
    }

    private fun resampleLinear(input: FloatArray, fromRate: Int, toRate: Int): FloatArray {
        require(fromRate > 0)
        if (fromRate == toRate) return input
        val outputSize = ceil(input.size * toRate.toDouble() / fromRate).toInt().coerceAtLeast(1)
        return FloatArray(outputSize) { index ->
            val position = index * fromRate.toDouble() / toRate
            val lower = floor(position).toInt().coerceIn(0, input.lastIndex)
            val upper = (lower + 1).coerceAtMost(input.lastIndex)
            val fraction = (position - lower).toFloat()
            input[lower] + (input[upper] - input[lower]) * fraction
        }
    }

    private class FloatAccumulator(initialCapacity: Int = 65_536) {
        private var values = FloatArray(initialCapacity)
        private var size = 0

        fun add(value: Float) {
            if (size == values.size) values = values.copyOf(values.size * 2)
            values[size++] = value
        }

        fun toArray(): FloatArray = values.copyOf(size)
    }

    private companion object {
        const val TARGET_SAMPLE_RATE = 16_000
        const val TIMEOUT_US = 10_000L
    }
}
