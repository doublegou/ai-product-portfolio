package com.rivendell.stayword.processing

import android.app.Notification
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.rivendell.stayword.R
import com.rivendell.stayword.StayWordApplication
import com.rivendell.stayword.appContainer
import com.rivendell.stayword.domain.ProcessingState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

interface ProcessingCoordinator {
    fun enqueue(recordingId: String)
    fun cancel(recordingId: String)
    suspend fun restoreInterrupted()
}

class WorkManagerProcessingCoordinator(
    private val context: Context,
    private val workManager: WorkManager = WorkManager.getInstance(context),
) : ProcessingCoordinator {
    override fun enqueue(recordingId: String) {
        val request = OneTimeWorkRequestBuilder<RecordingProcessingWorker>()
            .setInputData(Data.Builder().putString(RecordingProcessingWorker.KEY_RECORDING_ID, recordingId).build())
            .addTag(tag(recordingId))
            .build()
        workManager.enqueueUniqueWork(GLOBAL_QUEUE, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }

    override fun cancel(recordingId: String) {
        // A node in the global chain must not be cancelled through WorkManager: cancellation would
        // cascade to every dependent recording. The worker observes the repository tombstone and
        // exits successfully at the next stage boundary, preserving the rest of the queue.
    }

    override suspend fun restoreInterrupted() {
        withContext(Dispatchers.IO) {
            context.appContainer.recordingRepository.interruptedRecordingIds().forEach { recordingId ->
                val alreadyScheduled = runCatching {
                    workManager.getWorkInfosByTag(tag(recordingId)).get()
                        .any { workInfo -> !workInfo.state.isFinished }
                }.getOrDefault(false)
                if (!alreadyScheduled) enqueue(recordingId)
            }
        }
    }

    private fun tag(recordingId: String) = "recording-processing-$recordingId"

    private companion object {
        const val GLOBAL_QUEUE = "stayword-processing-queue"
    }
}

class RecordingProcessingWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    private val container = appContext.appContainer
    private val repository = container.recordingRepository

    override suspend fun doWork(): Result {
        val recordingId = inputData.getString(KEY_RECORDING_ID) ?: return Result.failure()
        val recording = repository.getRecording(recordingId) ?: return Result.success()
        if (recording.deletedAt != null || recording.processingState == ProcessingState.COMPLETED) {
            return Result.success()
        }

        return try {
            setForeground(foregroundInfo(recording.title, ProcessingState.PREPARING, 0f))
            repository.updateProcessing(recordingId, ProcessingState.PREPARING, 0.04f)
            val root = container.modelInstaller.ensureInstalled()
            val prepared = container.audioPcmPreparer.prepare(
                container.audioFileStore.fileFor(recording.audioRelativePath),
            )
            ensureRecordingIsActive(recordingId)
            val transcript = container.transcriptionEngine.transcribe(prepared, root) { stage, progress ->
                ensureRecordingIsActive(recordingId)
                repository.updateProcessing(recordingId, stage, progress)
                setForeground(foregroundInfo(recording.title, stage, progress))
            }
            ensureRecordingIsActive(recordingId)
            repository.replaceTranscript(recordingId, transcript)
            repository.updateProcessing(recordingId, ProcessingState.SUMMARIZING, 0.84f)
            setForeground(foregroundInfo(recording.title, ProcessingState.SUMMARIZING, 0.84f))
            val summary = container.summaryEngine.summarize(transcript.joinToString("\n") { it.text })
            ensureRecordingIsActive(recordingId)
            repository.updateSummary(recordingId, summary)
            repository.updateProcessing(recordingId, ProcessingState.COMPLETED, 1f)
            Result.success()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: RecordingRemovedException) {
            Result.success()
        } catch (error: Throwable) {
            if (repository.getRecording(recordingId)?.deletedAt == null) {
                repository.updateProcessing(
                    recordingId,
                    ProcessingState.FAILED,
                    0f,
                    error.message ?: "On-device processing failed",
                )
            }
            // A failed recording must not poison the serial chain. Retry is an explicit UI action.
            Result.success(Data.Builder().putString("error", error.message).build())
        }
    }

    private suspend fun ensureRecordingIsActive(recordingId: String) {
        val current = repository.getRecording(recordingId)
        if (current == null || current.deletedAt != null) throw RecordingRemovedException()
    }

    private fun foregroundInfo(title: String, state: ProcessingState, progress: Float): ForegroundInfo {
        val notification = NotificationCompat.Builder(applicationContext, StayWordApplication.CHANNEL_PROCESSING)
            .setSmallIcon(R.drawable.ic_history)
            .setContentTitle(applicationContext.getString(R.string.processing_recording, title))
            .setContentText(state.localizedLabel(applicationContext))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, (progress.coerceIn(0f, 1f) * 100).toInt(), false)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .build()
        return if (Build.VERSION.SDK_INT >= 35) {
            ForegroundInfo(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING,
            )
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val KEY_RECORDING_ID = "recording_id"
        const val NOTIFICATION_ID = 2_003
    }
}

private class RecordingRemovedException : RuntimeException()

fun ProcessingState.localizedLabel(context: Context): String = context.getString(
    when (this) {
        ProcessingState.READY -> R.string.ready
        ProcessingState.PREPARING -> R.string.preparing
        ProcessingState.VAD -> R.string.detecting_speech
        ProcessingState.TRANSCRIBING -> R.string.transcribing
        ProcessingState.DIARIZING -> R.string.identifying_speakers
        ProcessingState.ALIGNING -> R.string.aligning_transcript
        ProcessingState.SUMMARIZING -> R.string.generating_summary
        ProcessingState.COMPLETED -> R.string.completed
        ProcessingState.FAILED -> R.string.processing_failed
    },
)
