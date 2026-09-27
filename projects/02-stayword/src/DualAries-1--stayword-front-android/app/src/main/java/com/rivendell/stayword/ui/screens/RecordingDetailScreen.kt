@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.rivendell.stayword.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Tab
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.rivendell.stayword.R
import com.rivendell.stayword.domain.AudioRecording
import com.rivendell.stayword.domain.ProcessingState
import com.rivendell.stayword.domain.RecordingFolder
import com.rivendell.stayword.domain.SummaryKind
import com.rivendell.stayword.media.PlaybackState
import com.rivendell.stayword.processing.localizedLabel
import com.rivendell.stayword.ui.components.LoadingContent
import com.rivendell.stayword.ui.components.MoveDialog
import com.rivendell.stayword.util.formatDuration

@Composable
fun RecordingDetailScreen(
    recording: AudioRecording?,
    playback: PlaybackState,
    folders: List<RecordingFolder>,
    showBack: Boolean,
    onBack: () -> Unit,
    onLoadPlayback: (AudioRecording) -> Unit,
    onTogglePlayback: () -> Unit,
    onSeek: (Long) -> Unit,
    onSkip: (Long) -> Unit,
    onEdit: (String) -> Unit,
    onFavorite: (String, Boolean) -> Unit,
    onMove: (String, String?) -> Unit,
    onDelete: (String) -> Unit,
    onRetry: (String) -> Unit,
) {
    if (recording == null) {
        LoadingContent(Modifier.fillMaxSize())
        return
    }
    var tab by remember(recording.id) { mutableIntStateOf(0) }
    var menuExpanded by remember { mutableStateOf(false) }
    var showMove by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }

    LaunchedEffect(recording.id) { onLoadPlayback(recording) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(recording.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    if (showBack) {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.navigate_back))
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { onFavorite(recording.id, !recording.isFavorite) }) {
                        Icon(
                            if (recording.isFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                            contentDescription = stringResource(
                                if (recording.isFavorite) R.string.unfavorite else R.string.favorite,
                            ),
                        )
                    }
                    IconButton(onClick = { onEdit(recording.id) }) {
                        Icon(Icons.Default.Edit, contentDescription = stringResource(R.string.edit))
                    }
                    Box {
                        IconButton(onClick = { menuExpanded = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.more_options))
                        }
                        DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.move)) },
                                leadingIcon = { Icon(Icons.Default.Folder, contentDescription = null) },
                                onClick = { menuExpanded = false; showMove = true },
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
                                leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                                onClick = { menuExpanded = false; showDelete = true },
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            PlaybackControls(
                recording = recording,
                playback = playback.takeIf { it.recordingId == recording.id }
                    ?: PlaybackState(recordingId = recording.id, durationMs = recording.durationMs),
                onTogglePlayback = onTogglePlayback,
                onSeek = onSeek,
                onSkip = onSkip,
            )
            PrimaryTabRow(selectedTabIndex = tab) {
                Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text(stringResource(R.string.summary)) })
                Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text(stringResource(R.string.transcript)) })
            }
            if (tab == 0) {
                SummaryPane(recording, onRetry, Modifier.weight(1f))
            } else {
                TranscriptPane(
                    recording = recording,
                    currentPositionMs = playback.takeIf { it.recordingId == recording.id }?.currentPositionMs ?: 0L,
                    onSeek = onSeek,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    if (showMove) {
        MoveDialog(
            folders = folders,
            onDismiss = { showMove = false },
            onMove = { folderId -> showMove = false; onMove(recording.id, folderId) },
        )
    }
    if (showDelete) {
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text(stringResource(R.string.confirm_delete_title)) },
            text = { Text(stringResource(R.string.confirm_delete_body)) },
            confirmButton = {
                TextButton(onClick = { showDelete = false; onDelete(recording.id); onBack() }) {
                    Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { showDelete = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun PlaybackControls(
    recording: AudioRecording,
    playback: PlaybackState,
    onTogglePlayback: () -> Unit,
    onSeek: (Long) -> Unit,
    onSkip: (Long) -> Unit,
) {
    val duration = playback.durationMs.takeIf { it > 0 } ?: recording.durationMs
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp)) {
        Slider(
            value = playback.currentPositionMs.coerceIn(0L, duration).toFloat(),
            onValueChange = { onSeek(it.toLong()) },
            valueRange = 0f..duration.coerceAtLeast(1L).toFloat(),
            modifier = Modifier.fillMaxWidth(),
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(formatDuration(playback.currentPositionMs), fontFamily = FontFamily.Monospace)
            Text(formatDuration(duration), fontFamily = FontFamily.Monospace)
        }
        Row(
            Modifier.fillMaxWidth().padding(top = 8.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { onSkip(-15_000) }, modifier = Modifier.size(56.dp)) {
                Icon(Icons.Default.FastRewind, contentDescription = stringResource(R.string.skip_back))
            }
            IconButton(onClick = onTogglePlayback, modifier = Modifier.size(72.dp)) {
                Icon(
                    if (playback.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = stringResource(if (playback.isPlaying) R.string.pause else R.string.play),
                    modifier = Modifier.size(40.dp),
                )
            }
            IconButton(onClick = { onSkip(15_000) }, modifier = Modifier.size(56.dp)) {
                Icon(Icons.Default.FastForward, contentDescription = stringResource(R.string.skip_forward))
            }
        }
    }
}

@Composable
private fun SummaryPane(
    recording: AudioRecording,
    onRetry: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    when {
        recording.processingState.isProcessing -> {
            Column(modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(recording.processingState.localizedLabel(context), style = MaterialTheme.typography.titleMedium)
                LinearProgressIndicator(
                    progress = { recording.processingProgress },
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(stringResource(R.string.processing_offline_hint), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        recording.processingState == ProcessingState.FAILED -> {
            Column(modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.processing_failed), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.error)
                Text(recording.failureMessage.orEmpty())
                Button(onClick = { onRetry(recording.id) }) { Text(stringResource(R.string.retry)) }
            }
        }
        recording.summaryText.isBlank() -> {
            Box(modifier, contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.no_summary), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        else -> {
            Column(
                modifier.verticalScroll(rememberScrollState()).padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        recording.summarySubject.ifBlank { stringResource(R.string.summary) },
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = {
                        copyText(context, recording.summaryText)
                    }) { Icon(Icons.Default.ContentCopy, contentDescription = stringResource(R.string.copy)) }
                }
                recording.summaryKind.labelRes()?.let { AssistChip(onClick = {}, label = { Text(stringResource(it)) }) }
                SelectionContainer {
                    Text(recording.summaryText, style = MaterialTheme.typography.bodyLarge)
                }
                if (recording.markers.isNotEmpty()) {
                    HorizontalDivider()
                    Text(stringResource(R.string.markers), style = MaterialTheme.typography.titleMedium)
                    recording.markers.sortedBy { it.timestampMs }.forEach { marker ->
                        Text("${formatDuration(marker.timestampMs)}  ${marker.title}")
                    }
                }
            }
        }
    }
}

@Composable
private fun TranscriptPane(
    recording: AudioRecording,
    currentPositionMs: Long,
    onSeek: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    if (recording.transcriptSegments.isEmpty()) {
        Box(modifier, contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.no_transcript), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }
    Column(modifier) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.End) {
            TextButton(onClick = { copyText(context, recording.transcriptText) }) {
                Icon(Icons.Default.ContentCopy, contentDescription = null)
                Text(stringResource(R.string.copy), modifier = Modifier.padding(start = 8.dp))
            }
        }
        LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
            items(recording.transcriptSegments.sortedBy { it.startMs }, key = { it.id }) { segment ->
                val active = currentPositionMs in segment.startMs..(segment.startMs + segment.durationMs)
                ListItem(
                    headlineContent = {
                        Text(
                            segment.speakerIndex?.let { stringResource(R.string.speaker_number, it + 1) }
                                ?: stringResource(R.string.speaker_unknown),
                            color = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                            fontWeight = FontWeight.SemiBold,
                        )
                    },
                    supportingContent = { SelectionContainer { Text(segment.text) } },
                    leadingContent = { Text(formatDuration(segment.startMs), fontFamily = FontFamily.Monospace) },
                    modifier = Modifier.fillMaxWidth().clickable { onSeek(segment.startMs) },
                )
                HorizontalDivider()
            }
        }
    }
}

@Composable
fun RecordingEditScreen(
    recording: AudioRecording?,
    onBack: () -> Unit,
    onSave: (String, String, String, String) -> Unit,
) {
    if (recording == null) {
        LoadingContent(Modifier.fillMaxSize())
        return
    }
    var title by remember(recording.id) { mutableStateOf(recording.title) }
    var subject by remember(recording.id) { mutableStateOf(recording.summarySubject) }
    var summary by remember(recording.id) { mutableStateOf(recording.summaryText) }
    var showDiscard by remember { mutableStateOf(false) }
    val dirty = title != recording.title || subject != recording.summarySubject || summary != recording.summaryText
    val requestBack = { if (dirty) showDiscard = true else onBack() }
    BackHandler(enabled = dirty, onBack = { showDiscard = true })

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.edit_recording)) },
                navigationIcon = {
                    IconButton(onClick = requestBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.navigate_back))
                    }
                },
                actions = {
                    TextButton(
                        onClick = { onSave(recording.id, title.trim(), subject.trim(), summary.trim()) },
                        enabled = title.isNotBlank(),
                    ) { Text(stringResource(R.string.save)) }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            OutlinedTextField(
                value = title,
                onValueChange = { title = it.take(160) },
                label = { Text(stringResource(R.string.recording_title)) },
                singleLine = true,
                isError = title.isBlank(),
                modifier = Modifier.fillMaxWidth(),
            )
            Text(stringResource(R.string.summary), style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                value = subject,
                onValueChange = { subject = it.take(200) },
                label = { Text(stringResource(R.string.subject)) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = summary,
                onValueChange = { summary = it },
                label = { Text(stringResource(R.string.summary_text)) },
                minLines = 7,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }

    if (showDiscard) {
        AlertDialog(
            onDismissRequest = { showDiscard = false },
            title = { Text(stringResource(R.string.discard_changes_title)) },
            confirmButton = {
                TextButton(onClick = { showDiscard = false; onBack() }) {
                    Text(stringResource(R.string.discard), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { showDiscard = false }) { Text(stringResource(R.string.keep_editing)) } },
        )
    }
}

private fun SummaryKind.labelRes(): Int? = when (this) {
    SummaryKind.NONE -> null
    SummaryKind.AICORE -> R.string.on_device_intelligent_summary
    SummaryKind.LOCAL_LITERT -> R.string.on_device_summary
    SummaryKind.EXTRACTIVE -> R.string.basic_summary
}

private fun copyText(context: Context, text: String) {
    val clipboard = context.getSystemService(ClipboardManager::class.java)
    clipboard.setPrimaryClip(ClipData.newPlainText(context.getString(R.string.app_name), text))
    Toast.makeText(context, context.getString(R.string.copied), Toast.LENGTH_SHORT).show()
}
