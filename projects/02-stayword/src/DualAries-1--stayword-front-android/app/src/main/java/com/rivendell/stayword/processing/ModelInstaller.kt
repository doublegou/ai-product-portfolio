package com.rivendell.stayword.processing

import android.content.Context
import android.os.StatFs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

sealed interface ModelInstallState {
    data object Idle : ModelInstallState
    data class Installing(val completed: Int, val total: Int) : ModelInstallState
    data object Ready : ModelInstallState
    data class Failed(val message: String) : ModelInstallState
}

@Serializable
data class ModelManifest(
    val version: Int,
    val files: List<ModelManifestFile>,
)

@Serializable
data class ModelManifestFile(
    val path: String,
    val bytes: Long,
    val sha256: String,
    val source: String,
    val license: String,
)

class ModelInstaller(private val context: Context) {
    private val mutex = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true }
    private val _state = MutableStateFlow<ModelInstallState>(ModelInstallState.Idle)
    val state: StateFlow<ModelInstallState> = _state.asStateFlow()

    val modelRoot: File
        get() = File(context.noBackupFilesDir, "models")

    fun prepareAsync() {
        scope.launch {
            runCatching { ensureInstalled() }
                .onFailure { _state.value = ModelInstallState.Failed(it.message ?: "Model setup failed") }
        }
    }

    suspend fun ensureInstalled(): File = mutex.withLock {
        withContext(Dispatchers.IO) {
            val manifest = readManifest()
            val root = modelRoot.apply { mkdirs() }
            val pending = manifest.files.filterNot { item ->
                val file = safeDestination(root, item.path)
                file.isFile && file.length() == item.bytes && sha256(file) == item.sha256
            }

            if (pending.isNotEmpty()) {
                val required = pending.sumOf { it.bytes } + 32L * 1024 * 1024
                check(StatFs(root.path).availableBytes >= required) {
                    "Not enough storage for offline models"
                }
            }

            pending.forEachIndexed { index, item ->
                _state.value = ModelInstallState.Installing(index, pending.size)
                val destination = safeDestination(root, item.path)
                destination.parentFile?.mkdirs()
                val partial = File(destination.parentFile, "${destination.name}.partial")
                partial.delete()
                try {
                    context.assets.open("models/${item.path}").use { input ->
                        partial.outputStream().use { output -> input.copyTo(output, DEFAULT_BUFFER_SIZE * 4) }
                    }
                    check(partial.length() == item.bytes && sha256(partial) == item.sha256) {
                        "Model verification failed: ${item.path}"
                    }
                    Files.move(
                        partial.toPath(),
                        destination.toPath(),
                        StandardCopyOption.ATOMIC_MOVE,
                        StandardCopyOption.REPLACE_EXISTING,
                    )
                } catch (error: Throwable) {
                    partial.delete()
                    throw error
                }
            }
            _state.value = ModelInstallState.Ready
            root
        }
    }

    private fun readManifest(): ModelManifest = context.assets.open("models/manifest.json")
        .bufferedReader()
        .use { json.decodeFromString(it.readText()) }

    private fun safeDestination(root: File, relativePath: String): File {
        require(relativePath.isNotBlank() && !relativePath.startsWith('/')) {
            "Invalid model path: $relativePath"
        }
        val destination = File(root, relativePath).canonicalFile
        val canonicalRoot = root.canonicalFile
        require(destination.path.startsWith(canonicalRoot.path + File.separator)) {
            "Model path escapes the installation directory: $relativePath"
        }
        return destination
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE * 4)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }
}
