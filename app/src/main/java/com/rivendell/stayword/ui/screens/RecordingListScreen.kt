package com.rivendell.stayword.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.DriveFileMove
import androidx.compose.material.icons.filled.AudioFile
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FileOpen
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowDpSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.unit.dp
import com.rivendell.stayword.R
import com.rivendell.stayword.domain.AudioRecording
import com.rivendell.stayword.domain.RecordingFilter
import com.rivendell.stayword.domain.RecordingFolder
import com.rivendell.stayword.ui.components.EmptyState
import com.rivendell.stayword.ui.components.MoveDialog
import com.rivendell.stayword.ui.components.NameDialog
import com.rivendell.stayword.ui.components.RecordingRow

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun RecordingListScreen(
    title: String,
    filter: RecordingFilter,
    recordings: List<AudioRecording>,
    folders: List<RecordingFolder>,
    query: String,
    onQueryChange: (String) -> Unit,
    onBack: () -> Unit,
    onRecord: () -> Unit,
    onImport: (Uri) -> Unit,
    onOpenDetail: (String) -> Unit,
    onFavorite: (Collection<String>, Boolean) -> Unit,
    onRename: (String, String) -> Unit,
    onMove: (Collection<String>, String?) -> Unit,
    onDelete: (Collection<String>) -> Unit,
    detailContent: @Composable (String, () -> Unit) -> Unit,
) {
    var selectedIds by remember { mutableStateOf(setOf<String>()) }
    var renameTarget by remember { mutableStateOf<AudioRecording?>(null) }
    var moveIds by remember { mutableStateOf<Set<String>?>(null) }
    var deleteIds by remember { mutableStateOf<Set<String>?>(null) }
    var wideSelectedId by remember { mutableStateOf<String?>(null) }
    val isWide = currentWindowDpSize().width >= 840.dp
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(onImport)
    }

    Scaffold(
        topBar = {
            if (selectedIds.isNotEmpty()) {
                TopAppBar(
                    title = {
                        Text(pluralStringResource(R.plurals.selected_count, selectedIds.size, selectedIds.size))
                    },
                    navigationIcon = {
                        IconButton(onClick = { selectedIds = emptySet() }) {
                            Icon(Icons.Default.Close, contentDescription = stringResource(R.string.close))
                        }
                    },
                    actions = {
                        IconButton(onClick = { onFavorite(selectedIds, true); selectedIds = emptySet() }) {
                            Icon(Icons.Default.Favorite, contentDescription = stringResource(R.string.favorite))
                        }
                        IconButton(onClick = { moveIds = selectedIds }) {
                            Icon(Icons.AutoMirrored.Filled.DriveFileMove, contentDescription = stringResource(R.string.move))
                        }
                        IconButton(onClick = { deleteIds = selectedIds }) {
                            Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.delete))
                        }
                    },
                )
            } else {
                TopAppBar(
                    title = { Text(title) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.navigate_back))
                        }
                    },
                    actions = {
                        IconButton(onClick = { importLauncher.launch(arrayOf("audio/*")) }) {
                            Icon(Icons.Default.FileOpen, contentDescription = stringResource(R.string.import_audio))
                        }
                    },
                )
            }
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = onRecord,
                icon = { Icon(Icons.Default.Mic, contentDescription = null) },
                text = { Text(stringResource(R.string.record)) },
            )
        },
    ) { padding ->
        Row(Modifier.fillMaxSize().padding(padding)) {
            RecordingListPane(
                recordings = recordings,
                query = query,
                onQueryChange = onQueryChange,
                selectedIds = selectedIds,
                onRowClick = { recording ->
                    if (selectedIds.isNotEmpty()) {
                        selectedIds = selectedIds.toggle(recording.id)
                    } else if (isWide) {
                        wideSelectedId = recording.id
                    } else {
                        onOpenDetail(recording.id)
                    }
                },
                onRowLongClick = { recording -> selectedIds = selectedIds.toggle(recording.id) },
                onFavorite = { recording -> onFavorite(listOf(recording.id), !recording.isFavorite) },
                onRename = { renameTarget = it },
                onMove = { moveIds = setOf(it.id) },
                onDelete = { deleteIds = setOf(it.id) },
                modifier = if (isWide) Modifier.weight(0.42f).fillMaxHeight() else Modifier.fillMaxSize(),
            )
            if (isWide) {
                VerticalDivider()
                Box(Modifier.weight(0.58f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                    wideSelectedId?.let { id -> detailContent(id) { wideSelectedId = null } } ?: EmptyState(
                        title = stringResource(R.string.select_recording),
                        body = stringResource(R.string.select_recording_body),
                    )
                }
            }
        }
    }

    renameTarget?.let { recording ->
        NameDialog(
            title = stringResource(R.string.rename),
            label = stringResource(R.string.recording_title),
            initialValue = recording.title,
            onDismiss = { renameTarget = null },
            onConfirm = { name -> renameTarget = null; onRename(recording.id, name) },
        )
    }
    moveIds?.let { ids ->
        MoveDialog(
            folders = folders,
            onDismiss = { moveIds = null },
            onMove = { folderId -> moveIds = null; onMove(ids, folderId); selectedIds = emptySet() },
        )
    }
    deleteIds?.let { ids ->
        AlertDialog(
            onDismissRequest = { deleteIds = null },
            title = { Text(stringResource(R.string.confirm_delete_title)) },
            text = { Text(stringResource(R.string.confirm_delete_body)) },
            confirmButton = {
                TextButton(onClick = { deleteIds = null; onDelete(ids); selectedIds = emptySet() }) {
                    Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { deleteIds = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecordingListPane(
    recordings: List<AudioRecording>,
    query: String,
    onQueryChange: (String) -> Unit,
    selectedIds: Set<String>,
    onRowClick: (AudioRecording) -> Unit,
    onRowLongClick: (AudioRecording) -> Unit,
    onFavorite: (AudioRecording) -> Unit,
    onRename: (AudioRecording) -> Unit,
    onMove: (AudioRecording) -> Unit,
    onDelete: (AudioRecording) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier) {
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            label = { Text(stringResource(R.string.search_recordings)) },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            trailingIcon = {
                if (query.isNotEmpty()) {
                    IconButton(onClick = { onQueryChange("") }) {
                        Icon(Icons.Default.Clear, contentDescription = stringResource(R.string.clear_search))
                    }
                }
            },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        )
        if (recordings.isEmpty()) {
            EmptyState(
                title = stringResource(if (query.isBlank()) R.string.empty_library_title else R.string.empty_search_title),
                body = stringResource(if (query.isBlank()) R.string.empty_library_body else R.string.empty_search_body),
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            LazyColumn(contentPadding = PaddingValues(bottom = 104.dp)) {
                items(recordings, key = { it.id }) { recording ->
                    val dismissState = androidx.compose.material3.rememberSwipeToDismissBoxState(
                        confirmValueChange = { value ->
                            when (value) {
                                SwipeToDismissBoxValue.StartToEnd -> onFavorite(recording)
                                SwipeToDismissBoxValue.EndToStart -> onDelete(recording)
                                SwipeToDismissBoxValue.Settled -> Unit
                            }
                            false
                        },
                    )
                    SwipeToDismissBox(
                        state = dismissState,
                        enableDismissFromStartToEnd = selectedIds.isEmpty(),
                        enableDismissFromEndToStart = selectedIds.isEmpty(),
                        backgroundContent = {
                            Row(
                                Modifier.fillMaxSize().padding(horizontal = 24.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(Icons.Default.Favorite, contentDescription = stringResource(R.string.favorite))
                                Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.delete), tint = MaterialTheme.colorScheme.error)
                            }
                        },
                    ) {
                        RecordingRow(
                            recording = recording,
                            selected = recording.id in selectedIds,
                            selectionMode = selectedIds.isNotEmpty(),
                            onClick = { onRowClick(recording) },
                            onLongClick = { onRowLongClick(recording) },
                            onToggleFavorite = { onFavorite(recording) },
                            onRename = { onRename(recording) },
                            onMove = { onMove(recording) },
                            onDelete = { onDelete(recording) },
                        )
                    }
                    HorizontalDivider()
                }
            }
        }
    }
}

private fun Set<String>.toggle(id: String): Set<String> = if (id in this) this - id else this + id
