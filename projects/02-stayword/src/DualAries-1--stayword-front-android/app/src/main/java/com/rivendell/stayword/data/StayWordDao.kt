package com.rivendell.stayword.data

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.OnConflictStrategy
import androidx.room3.Query
import androidx.room3.Transaction
import androidx.room3.Update
import androidx.room3.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface StayWordDao {
    @Query("SELECT * FROM folders ORDER BY sortOrder ASC, createdAt ASC")
    fun observeFolders(): Flow<List<FolderEntity>>

    @Query("SELECT * FROM folders ORDER BY sortOrder ASC, createdAt ASC")
    suspend fun getFolders(): List<FolderEntity>

    @Query("SELECT * FROM folders WHERE id = :id LIMIT 1")
    suspend fun getFolder(id: String): FolderEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertFolder(folder: FolderEntity)

    @Update
    suspend fun updateFolder(folder: FolderEntity)

    @Query("DELETE FROM folders WHERE id = :folderId")
    suspend fun deleteFolderRow(folderId: String)

    @Transaction
    suspend fun deleteFolderAndTrash(folderId: String, deletedAt: Long): List<String> {
        val recordingIds = getActiveRecordingIdsInFolder(folderId)
        trashFolderRecordings(folderId, deletedAt)
        deleteFolderRow(folderId)
        return recordingIds
    }

    @Query("SELECT id FROM recordings WHERE folderId = :folderId AND deletedAt IS NULL")
    suspend fun getActiveRecordingIdsInFolder(folderId: String): List<String>

    @Query("UPDATE recordings SET deletedAt = :deletedAt, folderId = NULL WHERE folderId = :folderId AND deletedAt IS NULL")
    suspend fun trashFolderRecordings(folderId: String, deletedAt: Long)

    @Transaction
    @Query(
        """
        SELECT * FROM recordings
        WHERE deletedAt IS NULL
          AND (:favoriteOnly = 0 OR isFavorite = 1)
          AND (:folderId IS NULL OR folderId = :folderId)
          AND (
            :query = ''
            OR title LIKE '%' || :query || '%' ESCAPE '\' COLLATE NOCASE
            OR summarySubject LIKE '%' || :query || '%' ESCAPE '\' COLLATE NOCASE
            OR summaryText LIKE '%' || :query || '%' ESCAPE '\' COLLATE NOCASE
            OR EXISTS(
              SELECT 1 FROM transcript_segments
              WHERE transcript_segments.recordingId = recordings.id
                AND transcript_segments.text LIKE '%' || :query || '%' ESCAPE '\' COLLATE NOCASE
            )
          )
        ORDER BY createdAt DESC
        """,
    )
    fun observeRecordings(
        favoriteOnly: Int,
        folderId: String?,
        query: String,
    ): Flow<List<RecordingAggregate>>

    @Transaction
    @Query("SELECT * FROM recordings WHERE deletedAt IS NOT NULL ORDER BY deletedAt DESC")
    fun observeDeletedRecordings(): Flow<List<RecordingAggregate>>

    @Transaction
    @Query("SELECT * FROM recordings WHERE id = :id LIMIT 1")
    fun observeRecording(id: String): Flow<RecordingAggregate?>

    @Transaction
    @Query("SELECT * FROM recordings WHERE id = :id LIMIT 1")
    suspend fun getRecording(id: String): RecordingAggregate?

    @Query("SELECT * FROM recordings WHERE id = :id LIMIT 1")
    suspend fun getRecordingEntity(id: String): RecordingEntity?

    @Query("SELECT * FROM recordings WHERE deletedAt IS NULL ORDER BY createdAt DESC LIMIT 1")
    suspend fun getMostRecentRecording(): RecordingEntity?

    @Query("SELECT * FROM recordings WHERE deletedAt IS NULL AND processingState IN ('PREPARING','VAD','TRANSCRIBING','DIARIZING','ALIGNING','SUMMARIZING')")
    suspend fun getInterruptedRecordings(): List<RecordingEntity>

    @Upsert
    suspend fun upsertRecording(recording: RecordingEntity)

    @Query("UPDATE recordings SET title = :title WHERE id = :id")
    suspend fun renameRecording(id: String, title: String)

    @Query("UPDATE recordings SET isFavorite = :favorite WHERE id IN (:ids)")
    suspend fun setFavorite(ids: Collection<String>, favorite: Boolean)

    @Query("UPDATE recordings SET folderId = :folderId WHERE id IN (:ids)")
    suspend fun moveRecordings(ids: Collection<String>, folderId: String?)

    @Query("UPDATE recordings SET deletedAt = :deletedAt WHERE id IN (:ids)")
    suspend fun trashRecordings(ids: Collection<String>, deletedAt: Long)

    @Query("UPDATE recordings SET deletedAt = NULL WHERE id IN (:ids)")
    suspend fun restoreRecordings(ids: Collection<String>)

    @Query("DELETE FROM recordings WHERE id IN (:ids)")
    suspend fun deleteRecordings(ids: Collection<String>)

    @Query("UPDATE recordings SET processingState = :state, processingProgress = :progress, failureMessage = :failureMessage WHERE id = :id")
    suspend fun updateProcessingState(id: String, state: String, progress: Float, failureMessage: String?)

    @Query("UPDATE recordings SET summaryKind = :kind, summarySubject = :subject, summaryText = :text WHERE id = :id")
    suspend fun updateSummary(id: String, kind: String, subject: String, text: String)

    @Query("DELETE FROM transcript_segments WHERE recordingId = :recordingId")
    suspend fun deleteTranscript(recordingId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTranscript(segments: List<TranscriptSegmentEntity>)

    @Transaction
    suspend fun replaceTranscript(recordingId: String, segments: List<TranscriptSegmentEntity>) {
        deleteTranscript(recordingId)
        insertTranscript(segments)
    }
}
