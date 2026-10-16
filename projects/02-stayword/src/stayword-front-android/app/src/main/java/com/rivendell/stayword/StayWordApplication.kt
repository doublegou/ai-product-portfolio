package com.rivendell.stayword

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import com.rivendell.stayword.data.AudioFileStore
import com.rivendell.stayword.data.DefaultRecordingRepository
import com.rivendell.stayword.data.RecordingRepository
import com.rivendell.stayword.data.StayWordDatabase
import com.rivendell.stayword.processing.AudioPcmPreparer
import com.rivendell.stayword.processing.HybridSummaryEngine
import com.rivendell.stayword.processing.MediaCodecAudioPcmPreparer
import com.rivendell.stayword.processing.ModelInstaller
import com.rivendell.stayword.processing.ProcessingCoordinator
import com.rivendell.stayword.processing.SherpaTranscriptionEngine
import com.rivendell.stayword.processing.SummaryEngine
import com.rivendell.stayword.processing.TranscriptionEngine
import com.rivendell.stayword.processing.WorkManagerProcessingCoordinator
import com.rivendell.stayword.media.RecordingController
import com.rivendell.stayword.media.ServiceRecordingController
import com.rivendell.stayword.media.Media3PlaybackController
import com.rivendell.stayword.media.PlaybackController
import com.rivendell.stayword.media.LocationTitleSuggester
import com.rivendell.stayword.media.SystemLocationTitleSuggester
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class StayWordApplication : Application() {
    val container: AppContainer by lazy { AppContainer(this) }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        container.modelInstaller.prepareAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            container.processingCoordinator.restoreInterrupted()
        }
    }

    private fun createNotificationChannels() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannels(
            listOf(
                NotificationChannel(
                    CHANNEL_RECORDING,
                    getString(R.string.recording_channel),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { description = getString(R.string.recording_channel_description) },
                NotificationChannel(
                    CHANNEL_PLAYBACK,
                    getString(R.string.playback_channel),
                    NotificationManager.IMPORTANCE_LOW,
                ),
                NotificationChannel(
                    CHANNEL_PROCESSING,
                    getString(R.string.processing_channel),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { description = getString(R.string.processing_channel_description) },
            ),
        )
    }

    companion object {
        const val CHANNEL_RECORDING = "recording"
        const val CHANNEL_PLAYBACK = "playback"
        const val CHANNEL_PROCESSING = "processing"
    }
}

class AppContainer(application: Application) {
    val database: StayWordDatabase = StayWordDatabase.create(application)
    val audioFileStore = AudioFileStore(application)
    val recordingRepository: RecordingRepository =
        DefaultRecordingRepository(database.dao(), audioFileStore)
    val recordingController: RecordingController = ServiceRecordingController(application)
    val playbackController: PlaybackController = Media3PlaybackController(application, audioFileStore)
    val locationTitleSuggester: LocationTitleSuggester = SystemLocationTitleSuggester(application)
    val modelInstaller = ModelInstaller(application)
    val audioPcmPreparer: AudioPcmPreparer = MediaCodecAudioPcmPreparer()
    val transcriptionEngine: TranscriptionEngine = SherpaTranscriptionEngine()
    val summaryEngine: SummaryEngine = HybridSummaryEngine(application, modelInstaller)
    val processingCoordinator: ProcessingCoordinator = WorkManagerProcessingCoordinator(application)
}

val android.content.Context.appContainer: AppContainer
    get() = (applicationContext as StayWordApplication).container
