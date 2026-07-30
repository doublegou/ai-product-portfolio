package com.rivendell.stayword.data

import android.media.MediaMetadataRetriever
import android.net.Uri
import com.rivendell.stayword.domain.AudioRecording
import com.rivendell.stayword.domain.ProcessingState
import com.rivendell.stayword.domain.RecordingDraft
import com.rivendell.stayword.domain.RecordingFilter
import com.rivendell.stayword.domain.RecordingFolder
import com.rivendell.stayword.domain.SummaryDraft
import com.rivendell.stayword.domain.SummaryKind
import com.rivendell.stayword.domain.TranscriptDraft
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.util.UUID

interface RecordingRepository {
    fun observeFolders(): Flow<List<RecordingFolder>>
    fun observeRecordings(filter: RecordingFilter, query: String): Flow<List<AudioRecording>>
    fun observeDeletedRecordings(): Flow<List<AudioRecording>>
    fun observeRecording(id: String): Flow<AudioRecording?>
    suspend fun getRecording(id: String): AudioRecording?
    suspend fun getMostRecentRecording(): AudioRecording?
    suspend fun createFolder(name: String): RecordingFolder
    suspend fun renameFolder(id: String, name: String)
    suspend fun reorderFolders(ids: List<String>)
    suspend fun deleteFolder(id: String): List<String>
    suspend fun addRecording(draft: RecordingDraft): AudioRecording
    suspend fun importAudio(uri: Uri): AudioRecording
    suspend fun renameRecording(id: String, title: String)
    suspend fun setFavorite(ids: Collection<String>, favorite: Boolean)
    suspend fun moveRecordings(ids: Collection<String>, folderId: String?)
    suspend fun trashRecordings(ids: Collection<String>)
    suspend fun restoreRecordings(ids: Collection<String>)
    suspend fun permanentlyDelete(ids: Collection<String>)
    suspend fun updateProcessing(id: String, state: ProcessingState, progress: Float, failure: String? = null)
    suspend fun replaceTranscript(id: String, transcript: List<TranscriptDraft>)
    suspend fun updateSummary(id: String, summary: SummaryDraft)
    suspend fun saveEdits(id: String, title: String, subject: String, summaryText: String)
    suspend fun interruptedRecordingIds(): List<String>
}

class DefaultRecordingRepository(
    private val dao: StayWordDao,
    private val files: AudioFileStore,
) : RecordingRepository {
    override fun observeFolders() = dao.observeFolders().map { rows -> rows.map { it.toDomain() } }

    override fun observeRecordings(filter: RecordingFilter, query: String): Flow<List<AudioRecording>> {
        val favoriteOnly = if (filter is RecordingFilter.Favorites) 1 else 0
        val folderId = (filter as? RecordingFilter.Folder)?.id
        return dao.observeRecordings(favoriteOnly, folderId, query.trim().escapeLikePattern())
            .map { rows -> rows.map { it.toDomain() } }
    }

    override fun observeDeletedRecordings() =
        dao.observeDeletedRecordings().map { rows -> rows.map { it.toDomain() } }

    override fun observeRecording(id: String) = dao.observeRecording(id).map { it?.toDomain() }

    override suspend fun getRecording(id: String) = dao.getRecording(id)?.toDomain()

    override suspend fun getMostRecentRecording() = dao.getMostRecentRecording()?.toDomain()

    override suspend fun createFolder(name: String): RecordingFolder {
        val cleaned = requireValidName(name)
        val nextOrder = (dao.getFolders().maxOfOrNull { it.sortOrder } ?: -1) + 1
        val entity = FolderEntity(UUID.randomUUID().toString(), cleaned, nextOrder, System.currentTimeMillis())
        dao.insertFolder(entity)
        return entity.toDomain()
    }

    override suspend fun renameFolder(id: String, name: String) {
        val current = requireNotNull(dao.getFolder(id))
        dao.updateFolder(current.copy(name = requireValidName(name)))
    }

    override suspend fun reorderFolders(ids: List<String>) {
        val byId = dao.getFolders().associateBy { it.id }
        ids.forEachIndexed { index, id -> byId[id]?.let { dao.updateFolder(it.copy(sortOrder = index)) } }
    }

    override suspend fun deleteFolder(id: String): List<String> =
        dao.deleteFolderAndTrash(id, System.currentTimeMillis())

    override suspend fun addRecording(draft: RecordingDraft): AudioRecording {
        val entity = RecordingEntity(
            id = UUID.randomUUID().toString(),
            title = RecordingNameValidator.validate(draft.title),
            createdAt = draft.createdAt,
            durationMs = draft.durationMs.coerceAtLeast(100L),
            audioRelativePath = draft.audioRelativePath,
            isFavorite = false,
            processingState = ProcessingState.READY.name,
            processingProgress = 0f,
            summaryKind = SummaryKind.NONE.name,
            summarySubject = "",
            summaryText = "",
            failureMessage = null,
            waveformJson = draft.waveform.toJson(),
            folderId = null,
            deletedAt = null,
        )
        dao.upsertRecording(entity)
        return entity.toDomain()
    }

    override suspend fun importAudio(uri: Uri): AudioRecording {
        val (file, suggestedTitle) = files.import(uri)
        return try {
            val retriever = MediaMetadataRetriever()
            val duration = try {
                retriever.setDataSource(file.path)
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 100L
            } finally {
                retriever.release()
            }
            addRecording(
                RecordingDraft(
                    title = suggestedTitle?.takeIf { it.isNotBlank() } ?: files.defaultRecordingTitle(),
                    durationMs = duration,
                    audioRelativePath = files.relativePath(file),
                ),
            )
        } catch (error: Throwable) {
            file.delete()
            throw error
        }
    }

    override suspend fun renameRecording(id: String, title: String) =
        dao.renameRecording(id, RecordingNameValidator.validate(title))

    override suspend fun setFavorite(ids: Collection<String>, favorite: Boolean) {
        if (ids.isNotEmpty()) dao.setFavorite(ids, favorite)
    }

    override suspend fun moveRecordings(ids: Collection<String>, folderId: String?) {
        if (ids.isNotEmpty()) dao.moveRecordings(ids, folderId)
    }

    override suspend fun trashRecordings(ids: Collection<String>) {
        if (ids.isNotEmpty()) dao.trashRecordings(ids, System.currentTimeMillis())
    }

    override suspend fun restoreRecordings(ids: Collection<String>) {
        if (ids.isNotEmpty()) dao.restoreRecordings(ids)
    }

    override suspend fun permanentlyDelete(ids: Collection<String>) {
        ids.mapNotNull { dao.getRecordingEntity(it) }.forEach { files.delete(it.audioRelativePath) }
        if (ids.isNotEmpty()) dao.deleteRecordings(ids)
    }

    override suspend fun updateProcessing(
        id: String,
        state: ProcessingState,
        progress: Float,
        failure: String?,
    ) = dao.updateProcessingState(id, state.name, progress.coerceIn(0f, 1f), failure)

    override suspend fun replaceTranscript(id: String, transcript: List<TranscriptDraft>) {
        dao.replaceTranscript(
            id,
            transcript.mapIndexed { index, draft ->
                TranscriptSegmentEntity(
                    id = UUID.randomUUID().toString(),
                    recordingId = id,
                    startMs = draft.startMs,
                    durationMs = draft.durationMs,
                    text = draft.text.trim(),
                    sortOrder = index,
                    speakerIndex = draft.speakerIndex,
                )
            },
        )
    }

    override suspend fun updateSummary(id: String, summary: SummaryDraft) =
        dao.updateSummary(id, summary.kind.name, summary.subject.trim(), summary.text.trim())

    override suspend fun saveEdits(id: String, title: String, subject: String, summaryText: String) {
        val current = requireNotNull(dao.getRecordingEntity(id))
        dao.renameRecording(id, RecordingNameValidator.validate(title))
        dao.updateSummary(id, current.summaryKind, subject.trim(), summaryText.trim())
    }

    override suspend fun interruptedRecordingIds() = dao.getInterruptedRecordings().map { it.id }

    private fun requireValidName(name: String): String = RecordingNameValidator.validate(name)
}

internal object RecordingNameValidator {
    fun validate(name: String): String {
        val cleaned = name.trim()
        require(cleaned.isNotEmpty()) { "Name cannot be empty" }
        require(cleaned.length <= 160) { "Name is too long" }
        return cleaned
    }
}

internal fun String.escapeLikePattern(): String = replace("\\", "\\\\")
    .replace("%", "\\%")
    .replace("_", "\\_")
