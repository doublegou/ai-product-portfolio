package com.rivendell.stayword.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rivendell.stayword.R
import com.rivendell.stayword.ui.StayWordViewModel
import com.rivendell.stayword.ui.components.RecordingWaveform
import com.rivendell.stayword.util.formatDuration

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordingFlowHost(
    visible: Boolean,
    viewModel: StayWordViewModel,
    onDismiss: () -> Unit,
    onSaved: (String) -> Unit,
) {
    val context = LocalContext.current
    val defaultRecordingTitle = stringResource(R.string.new_recording)
    val state by viewModel.recordingSession.collectAsStateWithLifecycle()
    var showMicrophonePrompt by remember { mutableStateOf(false) }
    var showLocationPrompt by remember { mutableStateOf(false) }
    var showCancelConfirmation by remember { mutableStateOf(false) }
    var attemptedStart by remember { mutableStateOf(false) }
    var askedLocation by remember { mutableStateOf(false) }

    val permissionsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        if (grants[Manifest.permission.RECORD_AUDIO] == true) {
            viewModel.startRecording(defaultRecordingTitle)
        } else {
            onDismiss()
        }
    }
    val locationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            viewModel.suggestLocationTitle(defaultRecordingTitle)
        }
    }

    LaunchedEffect(visible) {
        if (!visible) {
            attemptedStart = false
            askedLocation = false
            return@LaunchedEffect
        }
        if (!state.active && !attemptedStart) {
            attemptedStart = true
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
            ) {
                viewModel.startRecording(defaultRecordingTitle)
            } else {
                showMicrophonePrompt = true
            }
        }
    }

    LaunchedEffect(state.active) {
        if (state.active && !askedLocation) {
            askedLocation = true
            showLocationPrompt = true
        }
    }

    LaunchedEffect(state.lastSavedRecordingId) {
        state.lastSavedRecordingId?.let { id ->
            viewModel.clearLastSavedRecording()
            onSaved(id)
        }
    }

    if ((visible || state.active) && state.active) {
        val sheetState = rememberModalBottomSheetState(
            skipPartiallyExpanded = false,
            confirmValueChange = { value -> value != SheetValue.Hidden },
        )
        ModalBottomSheet(
            onDismissRequest = {},
            sheetState = sheetState,
        ) {
            RecordingSheetContent(
                title = state.title,
                elapsedMs = state.elapsedMs,
                amplitudes = state.amplitudes,
                paused = state.paused,
                onTitleChange = viewModel::updateRecordingTitle,
                onPauseResume = {
                    if (state.paused) viewModel.resumeRecording() else viewModel.pauseRecording()
                },
                onStop = viewModel::stopRecording,
                onCancel = { showCancelConfirmation = true },
            )
        }
    }

    if (showMicrophonePrompt) {
        AlertDialog(
            onDismissRequest = { showMicrophonePrompt = false; onDismiss() },
            title = { Text(stringResource(R.string.permission_microphone_title)) },
            text = { Text(stringResource(R.string.permission_microphone_body)) },
            confirmButton = {
                TextButton(onClick = {
                    showMicrophonePrompt = false
                    val permissions = buildList {
                        add(Manifest.permission.RECORD_AUDIO)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            add(Manifest.permission.POST_NOTIFICATIONS)
                        }
                    }.toTypedArray()
                    permissionsLauncher.launch(permissions)
                }) { Text(stringResource(R.string.continue_label)) }
            },
            dismissButton = {
                TextButton(onClick = { showMicrophonePrompt = false; onDismiss() }) {
                    Text(stringResource(R.string.not_now))
                }
            },
        )
    }

    if (showLocationPrompt) {
        AlertDialog(
            onDismissRequest = { showLocationPrompt = false },
            title = { Text(stringResource(R.string.permission_location_title)) },
            text = { Text(stringResource(R.string.permission_location_body)) },
            confirmButton = {
                TextButton(onClick = {
                    showLocationPrompt = false
                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        viewModel.suggestLocationTitle(defaultRecordingTitle)
                    } else {
                        locationLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
                    }
                }) { Text(stringResource(R.string.continue_label)) }
            },
            dismissButton = {
                TextButton(onClick = { showLocationPrompt = false }) { Text(stringResource(R.string.not_now)) }
            },
        )
    }

    if (showCancelConfirmation) {
        AlertDialog(
            onDismissRequest = { showCancelConfirmation = false },
            title = { Text(stringResource(R.string.cancel_recording_title)) },
            text = { Text(stringResource(R.string.cancel_recording_body)) },
            confirmButton = {
                TextButton(onClick = {
                    showCancelConfirmation = false
                    viewModel.cancelRecording()
                    onDismiss()
                }) { Text(stringResource(R.string.discard), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showCancelConfirmation = false }) { Text(stringResource(R.string.continue_recording)) }
            },
        )
    }

    if (!state.active && state.errorMessage != null && visible) {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.recording_stopped)) },
            text = { Text(state.errorMessage.orEmpty()) },
            confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) } },
        )
    }
}

@Composable
private fun RecordingSheetContent(
    title: String,
    elapsedMs: Long,
    amplitudes: List<Float>,
    paused: Boolean,
    onTitleChange: (String) -> Unit,
    onPauseResume: () -> Unit,
    onStop: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = title,
                onValueChange = { onTitleChange(it.take(160)) },
                label = { Text(stringResource(R.string.recording_title)) },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onCancel, modifier = Modifier.padding(start = 8.dp)) {
                Icon(Icons.Default.Close, contentDescription = stringResource(R.string.cancel))
            }
        }
        Spacer(Modifier.height(24.dp))
        Text(
            formatDuration(elapsedMs),
            style = MaterialTheme.typography.displaySmall.merge(
                TextStyle(fontFamily = FontFamily.Monospace),
            ),
        )
        Spacer(Modifier.height(24.dp))
        RecordingWaveform(
            amplitudes = amplitudes.takeLast(64),
            activeColor = if (paused) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.error,
            modifier = Modifier.fillMaxWidth().height(112.dp),
        )
        Spacer(Modifier.height(28.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) {
            FilledIconButton(onClick = onPauseResume, modifier = Modifier.size(64.dp)) {
                Icon(
                    if (paused) Icons.Default.PlayArrow else Icons.Default.Pause,
                    contentDescription = stringResource(if (paused) R.string.resume else R.string.pause),
                )
            }
            Button(onClick = onStop, modifier = Modifier.height(64.dp)) {
                Icon(Icons.Default.Stop, contentDescription = null)
                Text(stringResource(R.string.stop), modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}
