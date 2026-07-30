package com.rivendell.stayword.processing

import com.rivendell.stayword.domain.SummaryKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SummaryEngineTest {
    @Test
    fun duplicateDetectionIgnoresCaseAndPunctuation() {
        assertFalse(SummaryContentPolicy.isDistinct("Hello, WORLD!", "hello world"))
        assertTrue(SummaryContentPolicy.isDistinct("A short summary", "A much longer transcript"))
    }

    @Test
    fun extractiveFallbackIsDeterministicAndDeduplicated() {
        val transcript = "First decision. Repeated point. Repeated point. Final action."
        val first = ExtractiveSummaryEngine.summarize(transcript)
        val second = ExtractiveSummaryEngine.summarize(transcript)

        assertEquals(first, second)
        assertEquals(SummaryKind.EXTRACTIVE, first.kind)
        assertEquals(1, Regex("Repeated point").findAll(first.text).count())
    }
}
