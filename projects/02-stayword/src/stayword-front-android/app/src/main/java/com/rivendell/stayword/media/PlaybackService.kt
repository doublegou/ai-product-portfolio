package com.rivendell.stayword.media

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.rivendell.stayword.MainActivity
import com.rivendell.stayword.data.AudioFileStore
import com.rivendell.stayword.domain.AudioRecording
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class PlaybackService : MediaSessionService() {
    private var player: ExoPlayer? = null
    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val exoPlayer = ExoPlayer.Builder(this)
            .setSeekBackIncrementMs(15_000)
            .setSeekForwardIncrementMs(15_000)
            .build()
        val sessionActivity = PendingIntent.getActivity(
            this,
            20,
            Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("stayword://recent")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        player = exoPlayer
        mediaSession = MediaSession.Builder(this, exoPlayer)
            .setSessionActivity(sessionActivity)
            .build()
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
        mediaSession.takeIf {
            controllerInfo.isTrusted ||
                (controllerInfo.isPackageNameVerified && controllerInfo.packageName == packageName)
        }

    override fun onDestroy() {
        mediaSession?.release()
        player?.release()
        mediaSession = null
        player = null
        super.onDestroy()
    }
}

data class PlaybackState(
    val recordingId: String? = null,
    val title: String = "",
    val currentPositionMs: Long = 0,
    val durationMs: Long = 0,
    val isPlaying: Boolean = false,
    val isReady: Boolean = false,
)

interface PlaybackController {
    val state: StateFlow<PlaybackState>
    fun load(recording: AudioRecording)
    fun toggle()
    fun seekTo(positionMs: Long)
    fun skipBy(deltaMs: Long)
    fun stop()
}

class Media3PlaybackController(
    context: Context,
    private val files: AudioFileStore,
) : PlaybackController {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutableState = MutableStateFlow(PlaybackState())
    override val state: StateFlow<PlaybackState> = mutableState.asStateFlow()
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null
    private var pendingRecording: AudioRecording? = null
    private var positionJob: Job? = null

    init {
        connect()
    }

    override fun load(recording: AudioRecording) {
        pendingRecording = recording
        controller?.let { loadIntoController(it, recording) }
    }

    override fun toggle() {
        controller?.let { player -> if (player.isPlaying) player.pause() else player.play() }
    }

    override fun seekTo(positionMs: Long) {
        controller?.seekTo(positionMs.coerceIn(0L, mutableState.value.durationMs.coerceAtLeast(0L)))
        updateFromController()
    }

    override fun skipBy(deltaMs: Long) = seekTo(mutableState.value.currentPositionMs + deltaMs)

    override fun stop() {
        controller?.run {
            pause()
            seekTo(0)
            clearMediaItems()
        }
        mutableState.value = PlaybackState()
    }

    private fun connect() {
        val token = SessionToken(appContext, ComponentName(appContext, PlaybackService::class.java))
        val future = MediaController.Builder(appContext, token).buildAsync()
        controllerFuture = future
        future.addListener(
            {
                runCatching { future.get() }.onSuccess { mediaController ->
                    controller = mediaController
                    mediaController.addListener(
                        object : Player.Listener {
                            override fun onEvents(player: Player, events: Player.Events) = updateFromController()
                        },
                    )
                    pendingRecording?.let { loadIntoController(mediaController, it) }
                    startPositionUpdates()
                }
            },
            ContextCompat.getMainExecutor(appContext),
        )
    }

    private fun loadIntoController(controller: MediaController, recording: AudioRecording) {
        if (mutableState.value.recordingId == recording.id) return
        val mediaItem = MediaItem.Builder()
            .setMediaId(recording.id)
            .setUri(Uri.fromFile(files.fileFor(recording.audioRelativePath)))
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(recording.title)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE)
                    .build(),
            )
            .build()
        controller.setMediaItem(mediaItem)
        controller.prepare()
        mutableState.value = PlaybackState(
            recordingId = recording.id,
            title = recording.title,
            durationMs = recording.durationMs,
            isReady = true,
        )
    }

    private fun startPositionUpdates() {
        positionJob?.cancel()
        positionJob = scope.launch {
            while (isActive) {
                updateFromController()
                delay(250)
            }
        }
    }

    private fun updateFromController() {
        val player = controller ?: return
        val previous = mutableState.value
        if (previous.recordingId == null) return
        mutableState.value = previous.copy(
            currentPositionMs = player.currentPosition.coerceAtLeast(0L),
            durationMs = player.duration.takeIf { it > 0 } ?: previous.durationMs,
            isPlaying = player.isPlaying,
            isReady = player.playbackState != Player.STATE_IDLE,
        )
    }
}
