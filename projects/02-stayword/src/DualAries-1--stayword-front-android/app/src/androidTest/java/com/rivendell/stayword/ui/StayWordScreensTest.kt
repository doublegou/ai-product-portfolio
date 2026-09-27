package com.rivendell.stayword.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ApplicationProvider
import com.rivendell.stayword.R
import com.rivendell.stayword.domain.AudioRecording
import com.rivendell.stayword.domain.ProcessingState
import com.rivendell.stayword.domain.RecordingFilter
import com.rivendell.stayword.domain.SummaryKind
import com.rivendell.stayword.media.PlaybackState
import com.rivendell.stayword.processing.ModelInstallState
import com.rivendell.stayword.ui.screens.LibraryScreen
import com.rivendell.stayword.ui.screens.RecordingDetailScreen
import com.rivendell.stayword.ui.screens.RecordingListScreen
import com.rivendell.stayword.ui.theme.StayWordTheme
import org.junit.Rule
import org.junit.Test

class StayWordScreensTest {
    @get:Rule
    val compose = createComposeRule()

    private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun libraryShowsNativeDestinationsAndFolderDialog() {
        compose.setContent {
            StayWordTheme(dynamicColor = false) {
                LibraryScreen(
                    folders = emptyList(),
                    modelState = ModelInstallState.Ready,
                    onAll = {}, onFavorites = {}, onDeleted = {}, onFolder = {},
                    onCreateFolder = {}, onRenameFolder = { _, _ -> }, onDeleteFolder = {},
                    onReorderFolders = {}, onRecord = {},
                )
            }
        }

        compose.onNodeWithText(context.getString(R.string.all_recordings)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.favorites)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.recently_deleted)).assertIsDisplayed()
        compose.onNodeWithContentDescription(context.getString(R.string.new_folder)).performClick()
        compose.onNodeWithText(context.getString(R.string.folder_name)).assertIsDisplayed()
    }

    @Test
    fun listSearchCanExpandFromEmptyLibraryState() {
        compose.setContent {
            var query by remember { mutableStateOf("") }
            StayWordTheme(dynamicColor = false) {
                RecordingListScreen(
                    title = context.getString(R.string.all_recordings),
                    filter = RecordingFilter.All,
                    recordings = emptyList(),
                    folders = emptyList(),
                    query = query,
                    onQueryChange = { query = it },
                    onBack = {}, onRecord = {}, onImport = {}, onOpenDetail = {},
                    onFavorite = { _, _ -> }, onRename = { _, _ -> }, onMove = { _, _ -> },
                    onDelete = {}, detailContent = { _, _ -> },
                )
            }
        }

        compose.onNodeWithText(context.getString(R.string.empty_library_title)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.search_recordings)).performTextInput("missing")
        compose.onNodeWithText(context.getString(R.string.empty_search_title)).assertIsDisplayed()
        compose.onNodeWithContentDescription(context.getString(R.string.clear_search)).performClick()
        compose.onNodeWithText(context.getString(R.string.empty_library_title)).assertIsDisplayed()
    }

    @Test
    fun detailUsesSummaryAndTranscriptTabs() {
        compose.setContent {
            StayWordTheme(dynamicColor = false) {
                RecordingDetailScreen(
                    recording = recording(),
                    playback = PlaybackState(),
                    folders = emptyList(),
                    showBack = true,
                    onBack = {}, onLoadPlayback = {}, onTogglePlayback = {}, onSeek = {}, onSkip = {},
                    onEdit = {}, onFavorite = { _, _ -> }, onMove = { _, _ -> }, onDelete = {}, onRetry = {},
                )
            }
        }

        compose.onNodeWithText(context.getString(R.string.summary)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.transcript)).performClick()
        compose.onNodeWithText(context.getString(R.string.no_transcript)).assertIsDisplayed()
    }

    private fun recording() = AudioRecording(
        id = "recording",
        title = "Planning",
        createdAt = 1,
        durationMs = 60_000,
        audioRelativePath = "recordings/recording.m4a",
        isFavorite = false,
        processingState = ProcessingState.COMPLETED,
        processingProgress = 1f,
        summaryKind = SummaryKind.EXTRACTIVE,
        summarySubject = "Plan",
        summaryText = "A concise plan.",
        failureMessage = null,
        waveform = emptyList(),
        folderId = null,
        deletedAt = null,
    )
}
