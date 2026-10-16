package com.rivendell.stayword.data

import android.content.Context
import androidx.room3.Room
import androidx.sqlite.driver.AndroidSQLiteDriver
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class StayWordDatabaseTest {
    private lateinit var database: StayWordDatabase
    private lateinit var dao: StayWordDao

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder<StayWordDatabase>(context)
            .setDriver(AndroidSQLiteDriver())
            .setQueryCoroutineContext(Dispatchers.IO)
            .build()
        dao = database.dao()
    }

    @After
    fun tearDown() = database.close()

    @Test
    fun folderDeletionTrashesActiveRecordingsAndClearsEveryFolderReference() = runTest {
        dao.insertFolder(FolderEntity("folder", "Meetings", 0, 1))
        dao.upsertRecording(recording("active", folderId = "folder"))
        dao.upsertRecording(recording("already-deleted", folderId = "folder", deletedAt = 5))

        val affected = dao.deleteFolderAndTrash("folder", deletedAt = 10)

        assertEquals(listOf("active"), affected)
        assertEquals(10L, dao.getRecording("active")?.recording?.deletedAt)
        assertNull(dao.getRecording("active")?.recording?.folderId)
        assertEquals(5L, dao.getRecording("already-deleted")?.recording?.deletedAt)
        assertNull(dao.getRecording("already-deleted")?.recording?.folderId)
    }

    @Test
    fun searchIncludesSummaryAndTranscriptButTreatsWildcardsLiterally() = runTest {
        dao.upsertRecording(recording("one", title = "Quarterly sync", summary = "Budget approved"))
        dao.upsertRecording(recording("two", title = "100% complete"))
        dao.replaceTranscript(
            "one",
            listOf(TranscriptSegmentEntity("segment", "one", 0, 1_000, "Launch on Friday", 0, 0)),
        )

        assertEquals(listOf("one"), search("Budget").map { it.recording.id })
        assertEquals(listOf("one"), search("Friday").map { it.recording.id })
        assertEquals(listOf("two"), search("%".escapeLikePattern()).map { it.recording.id })
    }

    @Test
    fun restoreKeepsExistingFolderRelationship() = runTest {
        dao.insertFolder(FolderEntity("folder", "Meetings", 0, 1))
        dao.upsertRecording(recording("one", folderId = "folder"))
        dao.trashRecordings(listOf("one"), 10)
        dao.restoreRecordings(listOf("one"))

        val restored = dao.getRecording("one")?.recording
        assertNull(restored?.deletedAt)
        assertEquals("folder", restored?.folderId)
    }

    private suspend fun search(query: String): List<RecordingAggregate> =
        dao.observeRecordings(favoriteOnly = 0, folderId = null, query = query).first()

    private fun recording(
        id: String,
        title: String = id,
        summary: String = "",
        folderId: String? = null,
        deletedAt: Long? = null,
    ) = RecordingEntity(
        id = id,
        title = title,
        createdAt = 1,
        durationMs = 1_000,
        audioRelativePath = "recordings/$id.m4a",
        isFavorite = false,
        processingState = "READY",
        processingProgress = 0f,
        summaryKind = "NONE",
        summarySubject = "",
        summaryText = summary,
        failureMessage = null,
        waveformJson = "[]",
        folderId = folderId,
        deletedAt = deletedAt,
    )
}
