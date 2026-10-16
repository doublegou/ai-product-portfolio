package com.rivendell.stayword.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.rivendell.stayword.R
import com.rivendell.stayword.domain.RecordingFilter
import com.rivendell.stayword.ui.screens.LibraryScreen
import com.rivendell.stayword.ui.screens.RecentlyDeletedScreen
import com.rivendell.stayword.ui.screens.RecordingDetailScreen
import com.rivendell.stayword.ui.screens.RecordingEditScreen
import com.rivendell.stayword.ui.screens.RecordingFlowHost
import com.rivendell.stayword.ui.screens.RecordingListScreen
import kotlinx.serialization.Serializable

@Serializable
data object LibraryRoute : NavKey

@Serializable
enum class FilterKind { ALL, FAVORITES, FOLDER }

@Serializable
data class RecordingsRoute(
    val kind: FilterKind,
    val folderId: String? = null,
    val folderName: String? = null,
) : NavKey

@Serializable
data object DeletedRoute : NavKey

@Serializable
data class DetailRoute(val recordingId: String) : NavKey

@Serializable
data class EditRoute(val recordingId: String) : NavKey

@Composable
fun StayWordApp(
    viewModel: StayWordViewModel,
    deepLink: String?,
    onDeepLinkConsumed: () -> Unit,
) {
    val backStack = rememberNavBackStack(LibraryRoute)
    val folders by viewModel.folders.collectAsStateWithLifecycle(initialValue = emptyList())
    val deleted by viewModel.deletedRecordings.collectAsStateWithLifecycle(initialValue = emptyList())
    val playback by viewModel.playbackState.collectAsStateWithLifecycle()
    val modelState by viewModel.modelInstallState.collectAsStateWithLifecycle()
    var showRecording by rememberSaveable { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(Unit) {
        viewModel.messages.collect { snackbar.showSnackbar(it) }
    }

    LaunchedEffect(deepLink) {
        when {
            deepLink?.startsWith("stayword://recording") == true -> showRecording = true
            deepLink?.startsWith("stayword://recent") == true -> {
                viewModel.mostRecentRecordingId()?.let { id -> backStack.add(DetailRoute(id)) }
            }
        }
        if (deepLink != null) onDeepLinkConsumed()
    }

    Box(Modifier.fillMaxSize()) {
        NavDisplay(
            backStack = backStack,
            modifier = Modifier.fillMaxSize(),
            onBack = { if (backStack.size > 1) backStack.removeLastOrNull() },
            entryProvider = entryProvider {
                entry<LibraryRoute> {
                    LibraryScreen(
                        folders = folders,
                        modelState = modelState,
                        onAll = { backStack.add(RecordingsRoute(FilterKind.ALL)) },
                        onFavorites = { backStack.add(RecordingsRoute(FilterKind.FAVORITES)) },
                        onDeleted = { backStack.add(DeletedRoute) },
                        onFolder = { folder ->
                            backStack.add(RecordingsRoute(FilterKind.FOLDER, folder.id, folder.name))
                        },
                        onCreateFolder = viewModel::createFolder,
                        onRenameFolder = viewModel::renameFolder,
                        onDeleteFolder = viewModel::deleteFolder,
                        onReorderFolders = viewModel::reorderFolders,
                        onRecord = { showRecording = true },
                    )
                }
                entry<RecordingsRoute> { route ->
                    var query by rememberSaveable(route) { mutableStateOf("") }
                    val filter = when (route.kind) {
                        FilterKind.ALL -> RecordingFilter.All
                        FilterKind.FAVORITES -> RecordingFilter.Favorites
                        FilterKind.FOLDER -> RecordingFilter.Folder(
                            requireNotNull(route.folderId),
                            route.folderName.orEmpty(),
                        )
                    }
                    val recordings by viewModel.recordings(filter, query)
                        .collectAsStateWithLifecycle(initialValue = emptyList())
                    val title = when (route.kind) {
                        FilterKind.ALL -> stringResource(R.string.all_recordings)
                        FilterKind.FAVORITES -> stringResource(R.string.favorites)
                        FilterKind.FOLDER -> route.folderName.orEmpty()
                    }
                    RecordingListScreen(
                        title = title,
                        filter = filter,
                        recordings = recordings,
                        folders = folders,
                        query = query,
                        onQueryChange = { query = it },
                        onBack = { backStack.removeLastOrNull() },
                        onRecord = { showRecording = true },
                        onImport = { uri -> viewModel.importAudio(uri) },
                        onOpenDetail = { id -> backStack.add(DetailRoute(id)) },
                        onFavorite = viewModel::setFavorite,
                        onRename = viewModel::renameRecording,
                        onMove = viewModel::move,
                        onDelete = viewModel::trash,
                        detailContent = { id, closeDetail ->
                            val recording by viewModel.recording(id).collectAsStateWithLifecycle(initialValue = null)
                            RecordingDetailScreen(
                                recording = recording,
                                playback = playback,
                                folders = folders,
                                showBack = false,
                                onBack = closeDetail,
                                onLoadPlayback = viewModel::loadPlayback,
                                onTogglePlayback = viewModel::togglePlayback,
                                onSeek = viewModel::seekTo,
                                onSkip = viewModel::skipBy,
                                onEdit = { recordingId -> backStack.add(EditRoute(recordingId)) },
                                onFavorite = { recordingId, favorite -> viewModel.setFavorite(listOf(recordingId), favorite) },
                                onMove = { recordingId, folderId -> viewModel.move(listOf(recordingId), folderId) },
                                onDelete = { recordingId -> viewModel.trash(listOf(recordingId)) },
                                onRetry = viewModel::retry,
                            )
                        },
                    )
                }
                entry<DeletedRoute> {
                    RecentlyDeletedScreen(
                        recordings = deleted,
                        onBack = { backStack.removeLastOrNull() },
                        onRestore = viewModel::restore,
                        onDeletePermanently = viewModel::permanentlyDelete,
                    )
                }
                entry<DetailRoute> { route ->
                    val recording by viewModel.recording(route.recordingId)
                        .collectAsStateWithLifecycle(initialValue = null)
                    RecordingDetailScreen(
                        recording = recording,
                        playback = playback,
                        folders = folders,
                        showBack = true,
                        onBack = { backStack.removeLastOrNull() },
                        onLoadPlayback = viewModel::loadPlayback,
                        onTogglePlayback = viewModel::togglePlayback,
                        onSeek = viewModel::seekTo,
                        onSkip = viewModel::skipBy,
                        onEdit = { id -> backStack.add(EditRoute(id)) },
                        onFavorite = { id, favorite -> viewModel.setFavorite(listOf(id), favorite) },
                        onMove = { id, folderId -> viewModel.move(listOf(id), folderId) },
                        onDelete = { id -> viewModel.trash(listOf(id)) },
                        onRetry = viewModel::retry,
                    )
                }
                entry<EditRoute> { route ->
                    val recording by viewModel.recording(route.recordingId)
                        .collectAsStateWithLifecycle(initialValue = null)
                    RecordingEditScreen(
                        recording = recording,
                        onBack = { backStack.removeLastOrNull() },
                        onSave = { id, title, subject, summary ->
                            viewModel.saveEdits(id, title, subject, summary) {
                                backStack.removeLastOrNull()
                            }
                        },
                    )
                }
            },
        )

        SnackbarHost(
            hostState = snackbar,
            modifier = Modifier.align(Alignment.BottomCenter).padding(16.dp),
        )
    }

    RecordingFlowHost(
        visible = showRecording,
        viewModel = viewModel,
        onDismiss = { showRecording = false },
        onSaved = { id ->
            showRecording = false
            backStack.add(DetailRoute(id))
        },
    )
}
