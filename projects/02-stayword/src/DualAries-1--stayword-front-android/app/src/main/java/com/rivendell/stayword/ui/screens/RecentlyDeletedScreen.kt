@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.rivendell.stayword.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.unit.dp
import com.rivendell.stayword.R
import com.rivendell.stayword.domain.AudioRecording
import com.rivendell.stayword.ui.components.EmptyState
import com.rivendell.stayword.util.formatDuration
import com.rivendell.stayword.util.formatRecordingDate

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun RecentlyDeletedScreen(
    recordings: List<AudioRecording>,
    onBack: () -> Unit,
    onRestore: (Collection<String>) -> Unit,
    onDeletePermanently: (Collection<String>) -> Unit,
) {
    var selected by remember { mutableStateOf(setOf<String>()) }
    var pendingDelete by remember { mutableStateOf<Set<String>?>(null) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (selected.isEmpty()) stringResource(R.string.recently_deleted)
                        else pluralStringResource(R.plurals.selected_count, selected.size, selected.size),
                    )
                },
                navigationIcon = {
                    IconButton(onClick = if (selected.isEmpty()) onBack else ({ selected = emptySet() })) {
                        Icon(
                            if (selected.isEmpty()) Icons.AutoMirrored.Filled.ArrowBack else Icons.Default.Close,
                            contentDescription = stringResource(
                                if (selected.isEmpty()) R.string.navigate_back else R.string.close,
                            ),
                        )
                    }
                },
                actions = {
                    if (selected.isNotEmpty()) {
                        IconButton(onClick = { onRestore(selected); selected = emptySet() }) {
                            Icon(Icons.Default.Restore, contentDescription = stringResource(R.string.restore))
                        }
                        IconButton(onClick = { pendingDelete = selected }) {
                            Icon(Icons.Default.DeleteForever, contentDescription = stringResource(R.string.delete_permanently))
                        }
                    }
                },
            )
        },
    ) { padding ->
        if (recordings.isEmpty()) {
            EmptyState(
                title = stringResource(R.string.empty_deleted_title),
                body = stringResource(R.string.empty_deleted_body),
                modifier = Modifier.fillMaxSize().padding(padding),
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(bottom = 24.dp),
            ) {
                items(recordings, key = { it.id }) { recording ->
                    ListItem(
                        headlineContent = { Text(recording.title) },
                        supportingContent = {
                            Text("${formatRecordingDate(recording.createdAt)} · ${formatDuration(recording.durationMs)}")
                        },
                        leadingContent = {
                            Icon(
                                if (recording.id in selected) Icons.Default.CheckCircle else Icons.Default.GraphicEq,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        },
                        trailingContent = {
                            if (selected.isEmpty()) {
                                Row {
                                    IconButton(onClick = { onRestore(listOf(recording.id)) }) {
                                        Icon(Icons.Default.Restore, contentDescription = stringResource(R.string.restore))
                                    }
                                    IconButton(onClick = { pendingDelete = setOf(recording.id) }) {
                                        Icon(
                                            Icons.Default.DeleteForever,
                                            contentDescription = stringResource(R.string.delete_permanently),
                                            tint = MaterialTheme.colorScheme.error,
                                        )
                                    }
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .combinedClickable(
                                onClick = {
                                    if (selected.isNotEmpty()) selected = selected.toggle(recording.id)
                                },
                                onLongClick = { selected = selected.toggle(recording.id) },
                            ),
                    )
                    HorizontalDivider()
                }
            }
        }
    }

    pendingDelete?.let { ids ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text(stringResource(R.string.confirm_permanent_delete_title)) },
            text = { Text(stringResource(R.string.confirm_permanent_delete_body)) },
            confirmButton = {
                TextButton(onClick = { pendingDelete = null; onDeletePermanently(ids); selected = emptySet() }) {
                    Text(stringResource(R.string.delete_permanently), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

private fun Set<String>.toggle(id: String): Set<String> = if (id in this) this - id else this + id
