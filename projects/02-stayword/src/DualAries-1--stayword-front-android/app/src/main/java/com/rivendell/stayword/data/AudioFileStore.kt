package com.rivendell.stayword.data

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.rivendell.stayword.R
import java.io.File
import java.util.UUID

class AudioFileStore(private val context: Context) {
    private val recordingsDirectory: File
        get() = File(context.filesDir, "recordings").apply { mkdirs() }

    fun newRecordingFile(extension: String = "m4a"): File =
        File(recordingsDirectory, "${UUID.randomUUID()}.$extension")

    fun fileFor(relativePath: String): File {
        val canonicalRoot = recordingsDirectory.canonicalFile
        val candidate = File(context.filesDir, relativePath).canonicalFile
        require(candidate.path.startsWith(canonicalRoot.path + File.separator)) {
            "Recording path escapes internal storage"
        }
        return candidate
    }

    fun relativePath(file: File): String = file.relativeTo(context.filesDir).path

    fun defaultRecordingTitle(): String = context.getString(R.string.new_recording)

    fun delete(relativePath: String) {
        runCatching { fileFor(relativePath).delete() }
    }

    fun import(uri: Uri): Pair<File, String?> {
        val displayName = context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
        val extension = displayName?.substringAfterLast('.', "")
            ?.lowercase()
            ?.takeIf { it.matches(Regex("[a-z0-9]{1,5}")) }
            ?: "m4a"
        val destination = newRecordingFile(extension)
        try {
            context.contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "Unable to read selected audio" }
                destination.outputStream().use { output -> input.copyTo(output) }
            }
        } catch (error: Throwable) {
            destination.delete()
            throw error
        }
        return destination to displayName?.substringBeforeLast('.')
    }
}
