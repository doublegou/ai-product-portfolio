package com.rivendell.stayword.ui

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.rivendell.stayword.AppContainer
import com.rivendell.stayword.domain.AudioRecording
import com.rivendell.stayword.domain.RecordingFilter
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch

class StayWordViewModel(private val container: AppContainer) : ViewModel() {
    val folders = container.recordingRepository.observeFolders()
    val deletedRecordings = container.recordingRepository.observeDeletedRecordings()
    val recordingSession = container.recordingController.state
    val playbackState = container.playbackController.state
    val modelInstallState = container.modelInstaller.state

    private val mutableMessages = MutableSharedFlow<String>(extraBufferCapacity = 4)
    val messages: SharedFlow<String> = mutableMessages.asSharedFlow()

    fun recordings(filter: RecordingFilter, query: String) =
        container.recordingRepository.observeRecordings(filter, query)

    fun recording(id: String) = container.recordingRepository.observeRecording(id)

    fun createFolder(name: String) = action { container.recordingRepository.createFolder(name) }

    fun renameFolder(id: String, name: String) = action { container.recordingRepository.renameFolder(id, name) }

    fun deleteFolder(id: String) = action {
        container.recordingRepository.deleteFolder(id)
            .forEach(container.processingCoordinator::cancel)
    }

    fun reorderFolders(ids: List<String>) = action { container.recordingRepository.reorderFolders(ids) }

    fun importAudio(uri: Uri, onImported: (String) -> Unit = {}) = action {
        val recording = container.recordingRepository.importAudio(uri)
        container.processingCoordinator.enqueue(recording.id)
        onImported(recording.id)
    }

    fun renameRecording(id: String, name: String) = action {
        container.recordingRepository.renameRecording(id, name)
    }

    fun setFavorite(ids: Collection<String>, favorite: Boolean) = action {
        container.recordingRepository.setFavorite(ids, favorite)
    }

    fun move(ids: Collection<String>, folderId: String?) = action {
        container.recordingRepository.moveRecordings(ids, folderId)
    }

    fun trash(ids: Collection<String>) = action {
        ids.forEach(container.processingCoordinator::cancel)
        container.recordingRepository.trashRecordings(ids)
    }

    fun restore(ids: Collection<String>) = action {
        container.recordingRepository.restoreRecordings(ids)
        ids.forEach { id ->
            if (container.recordingRepository.getRecording(id)?.processingState?.isProcessing == true) {
                container.processingCoordinator.enqueue(id)
            }
        }
    }

    fun permanentlyDelete(ids: Collection<String>) = action {
        ids.forEach(container.processingCoordinator::cancel)
        container.recordingRepository.permanentlyDelete(ids)
    }

    fun retry(recordingId: String) {
        container.processingCoordinator.enqueue(recordingId)
    }

    fun saveEdits(id: String, title: String, subject: String, summary: String, onSaved: () -> Unit) = action {
        container.recordingRepository.saveEdits(id, title, subject, summary)
        onSaved()
    }

    fun loadPlayback(recording: AudioRecording) = container.playbackController.load(recording)
    fun togglePlayback() = container.playbackController.toggle()
    fun seekTo(positionMs: Long) = container.playbackController.seekTo(positionMs)
    fun skipBy(deltaMs: Long) = container.playbackController.skipBy(deltaMs)
    fun stopPlayback() = container.playbackController.stop()

    fun startRecording(title: String) = container.recordingController.start(title)
    fun pauseRecording() = container.recordingController.pause()
    fun resumeRecording() = container.recordingController.resume()
    fun stopRecording() = container.recordingController.stop()
    fun cancelRecording() = container.recordingController.cancel()
    fun updateRecordingTitle(title: String) = container.recordingController.updateTitle(title)
    fun clearLastSavedRecording() = container.recordingController.clearLastSaved()

    fun suggestLocationTitle(defaultTitle: String) = viewModelScope.launch {
        val suggestion = runCatching { container.locationTitleSuggester.suggest() }.getOrNull()
        if (suggestion != null && container.recordingController.state.value.title == defaultTitle) {
            container.recordingController.updateTitle(suggestion)
        }
    }

    suspend fun mostRecentRecordingId(): String? =
        container.recordingRepository.getMostRecentRecording()?.id

    private fun action(block: suspend () -> Unit) {
        viewModelScope.launch {
            runCatching { block() }
                .onFailure { mutableMessages.emit(it.message ?: "Something went wrong") }
        }
    }

    companion object {
        fun factory(container: AppContainer): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T =
                    StayWordViewModel(container) as T
            }
    }
}
