package com.rivendell.stayword.media

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.rivendell.stayword.MainActivity
import com.rivendell.stayword.R
import com.rivendell.stayword.StayWordApplication
import com.rivendell.stayword.appContainer
import com.rivendell.stayword.domain.RecordingDraft
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.io.File

data class RecordingSessionState(
    val active: Boolean = false,
    val paused: Boolean = false,
    val elapsedMs: Long = 0,
    val title: String = "",
    val amplitudes: List<Float> = List(48) { 0.08f },
    val errorMessage: String? = null,
    val lastSavedRecordingId: String? = null,
)

object RecordingSession {
    private val mutableState = MutableStateFlow(RecordingSessionState())
    val state: StateFlow<RecordingSessionState> = mutableState.asStateFlow()

    internal fun update(block: (RecordingSessionState) -> RecordingSessionState) {
        mutableState.value = block(mutableState.value)
    }

    fun clearLastSaved() = update { it.copy(lastSavedRecordingId = null) }
}

interface RecordingController {
    val state: StateFlow<RecordingSessionState>
    fun start(title: String)
    fun pause()
    fun resume()
    fun stop()
    fun cancel()
    fun updateTitle(title: String)
    fun clearLastSaved()
}

class ServiceRecordingController(private val context: Context) : RecordingController {
    override val state = RecordingSession.state

    override fun start(title: String) = send(RecordingService.ACTION_START, title)
    override fun pause() = send(RecordingService.ACTION_PAUSE)
    override fun resume() = send(RecordingService.ACTION_RESUME)
    override fun stop() = send(RecordingService.ACTION_STOP)
    override fun cancel() = send(RecordingService.ACTION_CANCEL)
    override fun updateTitle(title: String) = send(RecordingService.ACTION_SET_TITLE, title)
    override fun clearLastSaved() = RecordingSession.clearLastSaved()

    private fun send(action: String, title: String? = null) {
        val intent = Intent(context, RecordingService::class.java).setAction(action)
        if (title != null) intent.putExtra(RecordingService.EXTRA_TITLE, title)
        if (action == RecordingService.ACTION_START) {
            ContextCompat.startForegroundService(context, intent)
        } else {
            context.startService(intent)
        }
    }
}

class RecordingService : Service(), MediaRecorder.OnErrorListener {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val audioManager by lazy { getSystemService(AudioManager::class.java) }
    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null
    private var meterJob: Job? = null
    private var segmentStartedAt = 0L
    private var elapsedBeforeSegment = 0L
    private var audioFocusRequest: AudioFocusRequest? = null
    private var isFinalizing = false

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            if (removedDevices.any { it.isSource } && RecordingSession.state.value.active) {
                finishAndSave(getString(R.string.recording_route_changed))
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        audioManager.registerAudioDeviceCallback(deviceCallback, null)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startRecording(intent.getStringExtra(EXTRA_TITLE))
            ACTION_PAUSE -> pauseRecording()
            ACTION_RESUME -> resumeRecording()
            ACTION_STOP -> finishAndSave()
            ACTION_CANCEL -> cancelRecording()
            ACTION_SET_TITLE -> intent.getStringExtra(EXTRA_TITLE)?.let(::updateTitle)
        }
        return if (RecordingSession.state.value.active) START_STICKY else START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onError(mr: MediaRecorder?, what: Int, extra: Int) {
        finishAndSave(getString(R.string.recording_stopped_unexpectedly))
    }

    override fun onDestroy() {
        if (RecordingSession.state.value.active && !isFinalizing) {
            saveSynchronouslyDuringShutdown(getString(R.string.recording_stopped_unexpectedly))
        }
        audioManager.unregisterAudioDeviceCallback(deviceCallback)
        abandonAudioFocus()
        meterJob?.cancel()
        scope.cancel()
        super.onDestroy()
    }

    private fun saveSynchronouslyDuringShutdown(message: String) {
        isFinalizing = true
        val finalState = RecordingSession.state.value
        val duration = currentElapsedMs().coerceAtLeast(100L)
        val file = outputFile
        stopNativeRecorder()
        if (file == null || !file.isFile || file.length() == 0L) {
            file?.delete()
            RecordingSession.update { RecordingSessionState(errorMessage = message) }
            return
        }
        runBlocking(Dispatchers.IO) {
            runCatching {
                val recording = appContainer.recordingRepository.addRecording(
                    RecordingDraft(
                        title = finalState.title.ifBlank { getString(R.string.new_recording) },
                        durationMs = duration,
                        audioRelativePath = appContainer.audioFileStore.relativePath(file),
                        waveform = finalState.amplitudes,
                    ),
                )
                appContainer.processingCoordinator.enqueue(recording.id)
                recording.id
            }.onSuccess { id ->
                RecordingSession.update {
                    RecordingSessionState(errorMessage = message, lastSavedRecordingId = id)
                }
            }.onFailure { error ->
                file.delete()
                RecordingSession.update { RecordingSessionState(errorMessage = error.message) }
            }
        }
    }

    private fun startRecording(requestedTitle: String?) {
        if (RecordingSession.state.value.active) return
        val file = appContainer.audioFileStore.newRecordingFile()
        try {
            requestAudioFocus()
            val mediaRecorder = MediaRecorder(this).apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(44_100)
                setAudioChannels(1)
                setAudioEncodingBitRate(96_000)
                setOutputFile(file.absolutePath)
                setOnErrorListener(this@RecordingService)
                prepare()
                start()
            }
            recorder = mediaRecorder
            outputFile = file
            elapsedBeforeSegment = 0L
            segmentStartedAt = SystemClock.elapsedRealtime()
            RecordingSession.update {
                RecordingSessionState(
                    active = true,
                    title = requestedTitle?.trim()?.takeIf { it.isNotEmpty() }
                        ?: getString(R.string.new_recording),
                )
            }
            val notification = buildNotification()
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
            startMetering()
        } catch (error: Throwable) {
            runCatching { recorder?.release() }
            recorder = null
            outputFile = null
            file.delete()
            RecordingSession.update { it.copy(active = false, errorMessage = error.message) }
            stopSelf()
        }
    }

    private fun pauseRecording() {
        val state = RecordingSession.state.value
        if (!state.active || state.paused) return
        runCatching {
            recorder?.pause()
            elapsedBeforeSegment = currentElapsedMs()
            RecordingSession.update { it.copy(paused = true, elapsedMs = elapsedBeforeSegment) }
            updateNotification()
        }.onFailure { finishAndSave(it.message) }
    }

    private fun resumeRecording() {
        val state = RecordingSession.state.value
        if (!state.active || !state.paused) return
        runCatching {
            recorder?.resume()
            segmentStartedAt = SystemClock.elapsedRealtime()
            RecordingSession.update { it.copy(paused = false, errorMessage = null) }
            updateNotification()
        }.onFailure { finishAndSave(it.message) }
    }

    private fun updateTitle(title: String) {
        val cleaned = title.trim().take(160)
        if (cleaned.isEmpty()) return
        RecordingSession.update { it.copy(title = cleaned) }
        updateNotification()
    }

    private fun finishAndSave(message: String? = null) {
        if (isFinalizing || !RecordingSession.state.value.active) return
        isFinalizing = true
        val finalState = RecordingSession.state.value
        val duration = currentElapsedMs().coerceAtLeast(100L)
        val file = outputFile
        stopNativeRecorder()
        if (file == null || !file.isFile || file.length() == 0L) {
            file?.delete()
            RecordingSession.update {
                RecordingSessionState(errorMessage = message ?: getString(R.string.recording_stopped_unexpectedly))
            }
            finishService()
            return
        }
        val fallbackTitle = getString(R.string.new_recording)
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val recording = appContainer.recordingRepository.addRecording(
                        RecordingDraft(
                            title = finalState.title.ifBlank { fallbackTitle },
                            durationMs = duration,
                            audioRelativePath = appContainer.audioFileStore.relativePath(file),
                            waveform = finalState.amplitudes,
                        ),
                    )
                    appContainer.processingCoordinator.enqueue(recording.id)
                    recording.id
                }
            }
            result.onSuccess { id ->
                RecordingSession.update {
                    RecordingSessionState(
                        errorMessage = message,
                        lastSavedRecordingId = id,
                    )
                }
            }.onFailure { error ->
                file.delete()
                RecordingSession.update { RecordingSessionState(errorMessage = error.message) }
            }
            finishService()
        }
    }

    private fun cancelRecording() {
        if (!RecordingSession.state.value.active) return
        isFinalizing = true
        stopNativeRecorder()
        outputFile?.delete()
        RecordingSession.update { RecordingSessionState() }
        finishService()
    }

    private fun stopNativeRecorder() {
        meterJob?.cancel()
        meterJob = null
        runCatching { recorder?.stop() }
        runCatching { recorder?.reset() }
        runCatching { recorder?.release() }
        recorder = null
        abandonAudioFocus()
    }

    private fun finishService() {
        outputFile = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        isFinalizing = false
    }

    private fun startMetering() {
        meterJob?.cancel()
        meterJob = scope.launch {
            while (isActive && RecordingSession.state.value.active) {
                val state = RecordingSession.state.value
                val elapsed = currentElapsedMs()
                if (!state.paused) {
                    val normalized = ((recorder?.maxAmplitude ?: 0) / 32_767f)
                        .coerceIn(0.04f, 1f)
                    val amplitudes = (state.amplitudes + normalized).takeLast(160)
                    RecordingSession.update { it.copy(elapsedMs = elapsed, amplitudes = amplitudes) }
                }
                if (elapsed / 1_000 != state.elapsedMs / 1_000) updateNotification()
                delay(50)
            }
        }
    }

    private fun currentElapsedMs(): Long {
        val state = RecordingSession.state.value
        return if (state.active && !state.paused) {
            elapsedBeforeSegment + (SystemClock.elapsedRealtime() - segmentStartedAt)
        } else {
            state.elapsedMs
        }
    }

    private fun buildNotification(): Notification {
        val state = RecordingSession.state.value
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("stayword://recording")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val pauseOrResume = if (state.paused) ACTION_RESUME else ACTION_PAUSE
        val pauseLabel = if (state.paused) R.string.resume else R.string.pause
        return NotificationCompat.Builder(this, StayWordApplication.CHANNEL_RECORDING)
            .setSmallIcon(R.drawable.ic_mic)
            .setContentTitle(state.title.ifBlank { getString(R.string.recording_in_progress) })
            .setContentText(if (state.paused) getString(R.string.pause) else getString(R.string.recording_in_progress))
            .setContentIntent(contentIntent)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setWhen(System.currentTimeMillis() - state.elapsedMs)
            .setUsesChronometer(!state.paused)
            .setRequestPromotedOngoing(true)
            .addAction(0, getString(pauseLabel), actionIntent(pauseOrResume, 1))
            .addAction(0, getString(R.string.stop), actionIntent(ACTION_STOP, 2))
            .build()
    }

    private fun actionIntent(action: String, requestCode: Int): PendingIntent = PendingIntent.getService(
        this,
        requestCode,
        Intent(this, RecordingService::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun updateNotification() {
        if (RecordingSession.state.value.active) {
            getSystemService(android.app.NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification())
        }
    }

    private fun requestAudioFocus() {
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setOnAudioFocusChangeListener { change ->
                if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
                    finishAndSave(getString(R.string.recording_interrupted))
                }
            }
            .build()
        audioFocusRequest = request
        audioManager.requestAudioFocus(request)
    }

    private fun abandonAudioFocus() {
        audioFocusRequest?.let(audioManager::abandonAudioFocusRequest)
        audioFocusRequest = null
    }

    companion object {
        const val ACTION_START = "com.rivendell.stayword.action.START_RECORDING"
        const val ACTION_PAUSE = "com.rivendell.stayword.action.PAUSE_RECORDING"
        const val ACTION_RESUME = "com.rivendell.stayword.action.RESUME_RECORDING"
        const val ACTION_STOP = "com.rivendell.stayword.action.STOP_RECORDING"
        const val ACTION_CANCEL = "com.rivendell.stayword.action.CANCEL_RECORDING"
        const val ACTION_SET_TITLE = "com.rivendell.stayword.action.SET_RECORDING_TITLE"
        const val EXTRA_TITLE = "title"
        const val NOTIFICATION_ID = 2_001
    }
}
