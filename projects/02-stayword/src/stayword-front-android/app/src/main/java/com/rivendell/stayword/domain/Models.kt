package com.rivendell.stayword.domain

enum class ProcessingState {
    READY,
    PREPARING,
    VAD,
    TRANSCRIBING,
    DIARIZING,
    ALIGNING,
    SUMMARIZING,
    COMPLETED,
    FAILED;

    val isProcessing: Boolean
        get() = this in setOf(PREPARING, VAD, TRANSCRIBING, DIARIZING, ALIGNING, SUMMARIZING)
}

enum class SummaryKind {
    NONE,
    AICORE,
    LOCAL_LITERT,
    EXTRACTIVE,
}

sealed interface RecordingFilter {
    data object All : RecordingFilter
    data object Favorites : RecordingFilter
    data class Folder(val id: String, val name: String) : RecordingFilter
}

data class RecordingFolder(
    val id: String,
    val name: String,
    val sortOrder: Int,
    val createdAt: Long,
)

data class TranscriptSegment(
    val id: String,
    val recordingId: String,
    val startMs: Long,
    val durationMs: Long,
    val text: String,
    val sortOrder: Int,
    val speakerIndex: Int?,
)

data class RecordingMarker(
    val id: String,
    val recordingId: String,
    val timestampMs: Long,
    val title: String,
)

data class AudioRecording(
    val id: String,
    val title: String,
    val createdAt: Long,
    val durationMs: Long,
    val audioRelativePath: String,
    val isFavorite: Boolean,
    val processingState: ProcessingState,
    val processingProgress: Float,
    val summaryKind: SummaryKind,
    val summarySubject: String,
    val summaryText: String,
    val failureMessage: String?,
    val waveform: List<Float>,
    val folderId: String?,
    val deletedAt: Long?,
    val transcriptSegments: List<TranscriptSegment> = emptyList(),
    val markers: List<RecordingMarker> = emptyList(),
) {
    val transcriptText: String
        get() = transcriptSegments.sortedBy { it.startMs }.joinToString("\n") { it.text }
}

data class RecordingDraft(
    val title: String,
    val durationMs: Long,
    val audioRelativePath: String,
    val waveform: List<Float> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
)

data class TranscriptDraft(
    val startMs: Long,
    val durationMs: Long,
    val text: String,
    val speakerIndex: Int?,
)

data class SummaryDraft(
    val subject: String,
    val text: String,
    val kind: SummaryKind,
)
