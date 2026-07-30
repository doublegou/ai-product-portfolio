package com.rivendell.stayword.processing

import android.content.Context
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.rivendell.stayword.domain.SummaryDraft
import com.rivendell.stayword.domain.SummaryKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

interface SummaryEngine {
    suspend fun summarize(transcript: String): SummaryDraft
}

class HybridSummaryEngine(
    private val context: Context,
    private val modelInstaller: ModelInstaller,
) : SummaryEngine {
    override suspend fun summarize(transcript: String): SummaryDraft {
        val cleaned = transcript.trim()
        require(cleaned.isNotEmpty()) { "Transcript is empty" }

        if (isAppForeground()) {
            runCatching { summarizeWithAiCore(cleaned) }
                .getOrNull()
                ?.takeIf { SummaryContentPolicy.isDistinct(it.text, cleaned) }
                ?.let { return it }
        }

        runCatching { summarizeWithLiteRt(cleaned) }
            .getOrNull()
            ?.takeIf { SummaryContentPolicy.isDistinct(it.text, cleaned) }
            ?.let { return it }

        return ExtractiveSummaryEngine.summarize(cleaned)
    }

    private fun isAppForeground(): Boolean = ProcessLifecycleOwner.get().lifecycle.currentState
        .isAtLeast(Lifecycle.State.STARTED)

    private suspend fun summarizeWithAiCore(transcript: String): SummaryDraft {
        val client = Generation.getClient()
        try {
            check(client.checkStatus() == FeatureStatus.AVAILABLE) { "AICore is unavailable" }
            val notes = chunkText(transcript, 10_000).map { chunk ->
                client.generateContent(summaryPrompt(chunk)).candidates.firstOrNull()?.text
                    ?.takeIf { it.isNotBlank() }
                    ?: error("AICore returned no summary")
            }
            val output = if (notes.size == 1) notes.single() else {
                client.generateContent(consolidationPrompt(notes)).candidates.firstOrNull()?.text
                    ?: error("AICore returned no final summary")
            }
            return parseModelSummary(output, SummaryKind.AICORE)
        } finally {
            client.close()
        }
    }

    private suspend fun summarizeWithLiteRt(transcript: String): SummaryDraft = withContext(Dispatchers.Default) {
        val model = File(
            modelInstaller.ensureInstalled(),
            "summary/qwen3_0.6b_nothink_q4_block32_ekv1280.litertlm",
        )
        val output = runCatching { runLiteRt(model, transcript, Backend.GPU()) }
            .recoverCatching { runLiteRt(model, transcript, Backend.CPU(numOfThreads = 2)) }
            .getOrThrow()
        parseModelSummary(output, SummaryKind.LOCAL_LITERT)
    }

    private fun runLiteRt(model: File, transcript: String, backend: Backend): String {
        val engine = Engine(
            EngineConfig(
                modelPath = model.absolutePath,
                backend = backend,
                maxNumTokens = 4_096,
                cacheDir = File(context.cacheDir, "litertlm").apply { mkdirs() }.absolutePath,
            ),
        )
        try {
            engine.initialize()
            val notes = chunkText(transcript, 10_000).map { chunk ->
                generateLiteRt(engine, summaryPrompt(chunk))
            }
            return if (notes.size == 1) notes.single() else {
                generateLiteRt(engine, consolidationPrompt(notes))
            }
        } finally {
            engine.close()
        }
    }

    private fun generateLiteRt(engine: Engine, prompt: String): String {
        val conversation = engine.createConversation(
            ConversationConfig(
                systemInstruction = Contents.of(
                    "You summarize recordings accurately. Never invent facts. Follow the requested output format exactly.",
                ),
                samplerConfig = SamplerConfig(topK = 20, topP = 0.9, temperature = 0.2, seed = 42),
            ),
        )
        return try {
            conversation.sendMessage(prompt).contents.contents
                .filterIsInstance<Content.Text>()
                .joinToString("") { it.text }
                .trim()
                .also { require(it.isNotEmpty()) { "LiteRT-LM returned no summary" } }
        } finally {
            conversation.close()
        }
    }

    private fun summaryPrompt(transcript: String): String = """
        Summarize the recording transcript below in the transcript's language.
        Create a short subject and a concise, useful summary. Preserve decisions, names, dates, and action items.
        Do not copy the transcript verbatim and do not add information.

        Return exactly this structure:
        SUBJECT: one short line
        SUMMARY:
        summary text

        TRANSCRIPT:
        $transcript
    """.trimIndent()

    private fun consolidationPrompt(notes: List<String>): String = """
        Combine these partial recording summaries into one coherent summary. Remove repetition and keep all important decisions and action items.
        Return exactly this structure:
        SUBJECT: one short line
        SUMMARY:
        summary text

        PARTIAL SUMMARIES:
        ${notes.joinToString("\n\n---\n\n")}
    """.trimIndent()

    private fun parseModelSummary(raw: String, kind: SummaryKind): SummaryDraft {
        val cleaned = raw.replace(Regex("^```[a-zA-Z]*|```$"), "").trim()
        val subjectMatch = Regex("(?im)^\\s*(?:SUBJECT|主题|标题)\\s*[:：]\\s*(.+)$").find(cleaned)
        val summaryMarker = Regex("(?im)^\\s*(?:SUMMARY|摘要)\\s*[:：]\\s*").find(cleaned)
        val subject = subjectMatch?.groupValues?.get(1)?.trim()?.take(120)
            ?: cleaned.lineSequence().firstOrNull { it.isNotBlank() }?.take(120)
            ?: "Recording"
        val text = summaryMarker?.let { cleaned.substring(it.range.last + 1).trim() }
            ?: cleaned.lineSequence().drop(1).joinToString("\n").trim().ifEmpty { cleaned }
        require(text.isNotBlank()) { "Generated summary is empty" }
        return SummaryDraft(subject = subject, text = text, kind = kind)
    }

    private fun chunkText(text: String, maxChars: Int): List<String> {
        if (text.length <= maxChars) return listOf(text)
        val paragraphs = text.split(Regex("\\n+"))
        val chunks = mutableListOf<String>()
        val current = StringBuilder()
        paragraphs.forEach { paragraph ->
            if (current.isNotEmpty() && current.length + paragraph.length + 1 > maxChars) {
                chunks += current.toString()
                current.clear()
            }
            if (paragraph.length > maxChars) {
                paragraph.chunked(maxChars).forEach { piece ->
                    if (current.isNotEmpty()) {
                        chunks += current.toString()
                        current.clear()
                    }
                    chunks += piece
                }
            } else {
                if (current.isNotEmpty()) current.append('\n')
                current.append(paragraph)
            }
        }
        if (current.isNotEmpty()) chunks += current.toString()
        return chunks
    }
}

object SummaryContentPolicy {
    fun isDistinct(summary: String, transcript: String): Boolean {
        val normalizedSummary = normalize(summary)
        val normalizedTranscript = normalize(transcript)
        return normalizedSummary.isNotEmpty() && normalizedSummary != normalizedTranscript
    }

    private fun normalize(value: String): String = value.lowercase()
        .replace(Regex("[^\\p{L}\\p{N}]+"), "")
}

object ExtractiveSummaryEngine {
    fun summarize(transcript: String): SummaryDraft {
        val sentences = transcript
            .split(Regex("(?<=[.!?。！？])\\s*|\\n+"))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        val subject = sentences.firstOrNull()?.take(80)?.trimEnd('.', '。', '!', '！', '?', '？')
            ?.takeIf { it.isNotBlank() }
            ?: "Recording"
        val selected = when {
            sentences.size <= 1 -> listOf("Key point: ${sentences.firstOrNull() ?: transcript.take(240)}")
            sentences.size <= 5 -> sentences
            else -> listOf(sentences.first(), sentences[sentences.size / 3], sentences[sentences.size * 2 / 3], sentences.last())
        }
        return SummaryDraft(
            subject = subject,
            text = selected.distinct().joinToString("\n• ", prefix = "• "),
            kind = SummaryKind.EXTRACTIVE,
        )
    }
}
