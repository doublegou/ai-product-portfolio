package com.rivendell.stayword.processing

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ModelManifestTest {
    @Test
    fun manifestIsVersionedCompleteAndUsesStrongDigests() {
        val manifestFile = File("src/main/assets/models/manifest.json")
        assertTrue("manifest.json must be committed", manifestFile.isFile)
        val manifest = Json.decodeFromString<ModelManifest>(manifestFile.readText())

        assertEquals(1, manifest.version)
        assertEquals(6, manifest.files.size)
        assertEquals(manifest.files.size, manifest.files.map { it.path }.distinct().size)
        manifest.files.forEach { entry ->
            assertTrue(entry.path.isNotBlank())
            assertTrue(entry.bytes > 0)
            assertTrue(entry.sha256.matches(Regex("[a-f0-9]{64}")))
            assertTrue(entry.source.startsWith("https://"))
            assertTrue(entry.license.isNotBlank())
        }
    }
}
