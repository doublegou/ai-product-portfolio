package com.rivendell.stayword.data

import androidx.room3.Embedded
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index
import androidx.room3.PrimaryKey
import androidx.room3.Relation
import com.rivendell.stayword.domain.AudioRecording
import com.rivendell.stayword.domain.ProcessingState
import com.rivendell.stayword.domain.RecordingFolder
import com.rivendell.stayword.domain.RecordingMarker
import com.rivendell.stayword.domain.SummaryKind
import com.rivendell.stayword.domain.TranscriptSegment
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Entity(tableName = "folders")
data class FolderEntity(
    @PrimaryKey val id: String,
    val name: String,
    val sortOrder: Int,
    val createdAt: Long,
)

@Entity(
    tableName = "recordings",
    foreignKeys = [
        ForeignKey(
            entity = FolderEntity::class,
            parentColumns = ["id"],
            childColumns = ["folderId"],
            onDelete = ForeignKey.SET_NULL,
        ),
    ],
    indices = [Index("folderId"), Index("createdAt"), Index("deletedAt")],
)
data class RecordingEntity(
    @PrimaryKey val id: String,
    val title: String,
    val createdAt: Long,
    val durationMs: Long,
    val audioRelativePath: String,
    val isFavorite: Boolean,
    val processingState: String,
    val processingProgress: Float,
    val summaryKind: String,
    val summarySubject: String,
    val summaryText: String,
    val failureMessage: String?,
    val waveformJson: String,
    val folderId: String?,
    val deletedAt: Long?,
)

@Entity(
    tableName = "transcript_segments",
    foreignKeys = [
        ForeignKey(
            entity = RecordingEntity::class,
            parentColumns = ["id"],
            childColumns = ["recordingId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("recordingId")],
)
data class TranscriptSegmentEntity(
    @PrimaryKey val id: String,
    val recordingId: String,
    val startMs: Long,
    val durationMs: Long,
    val text: String,
    val sortOrder: Int,
    val speakerIndex: Int?,
)

@Entity(
    tableName = "recording_markers",
    foreignKeys = [
        ForeignKey(
            entity = RecordingEntity::class,
            parentColumns = ["id"],
            childColumns = ["recordingId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("recordingId")],
)
data class RecordingMarkerEntity(
    @PrimaryKey val id: String,
    val recordingId: String,
    val timestampMs: Long,
    val title: String,
)

data class RecordingAggregate(
    @Embedded val recording: RecordingEntity,
    @Relation(parentColumns = ["id"], entityColumns = ["recordingId"])
    val transcriptSegments: List<TranscriptSegmentEntity>,
    @Relation(parentColumns = ["id"], entityColumns = ["recordingId"])
    val markers: List<RecordingMarkerEntity>,
)

internal val modelJson = Json { ignoreUnknownKeys = true }

fun FolderEntity.toDomain() = RecordingFolder(id, name, sortOrder, createdAt)

fun TranscriptSegmentEntity.toDomain() = TranscriptSegment(
    id = id,
    recordingId = recordingId,
    startMs = startMs,
    durationMs = durationMs,
    text = text,
    sortOrder = sortOrder,
    speakerIndex = speakerIndex,
)

fun RecordingMarkerEntity.toDomain() = RecordingMarker(id, recordingId, timestampMs, title)

fun RecordingAggregate.toDomain() = recording.toDomain(
    segments = transcriptSegments.map { it.toDomain() },
    markers = markers.map { it.toDomain() },
)

fun RecordingEntity.toDomain(
    segments: List<TranscriptSegment> = emptyList(),
    markers: List<RecordingMarker> = emptyList(),
) = AudioRecording(
    id = id,
    title = title,
    createdAt = createdAt,
    durationMs = durationMs,
    audioRelativePath = audioRelativePath,
    isFavorite = isFavorite,
    processingState = ProcessingState.entries.firstOrNull { it.name == processingState } ?: ProcessingState.READY,
    processingProgress = processingProgress,
    summaryKind = SummaryKind.entries.firstOrNull { it.name == summaryKind } ?: SummaryKind.NONE,
    summarySubject = summarySubject,
    summaryText = summaryText,
    failureMessage = failureMessage,
    waveform = runCatching { modelJson.decodeFromString<List<Float>>(waveformJson) }.getOrDefault(emptyList()),
    folderId = folderId,
    deletedAt = deletedAt,
    transcriptSegments = segments,
    markers = markers,
)

fun List<Float>.toJson(): String = modelJson.encodeToString(this)
