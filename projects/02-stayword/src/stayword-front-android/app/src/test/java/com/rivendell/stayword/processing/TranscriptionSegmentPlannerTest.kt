package com.rivendell.stayword.processing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TranscriptionSegmentPlannerTest {
    @Test
    fun normalizesSpeakersByFirstAppearance() {
        val units = TranscriptionSegmentPlanner.makeUnits(
            speech = listOf(SpeechInterval(0.0, 4.0)),
            speakerTurns = listOf(
                SpeakerTurn(0.0, 2.0, 7),
                SpeakerTurn(2.0, 4.0, 3),
            ),
            audioDurationSeconds = 4.0,
        )

        assertEquals(listOf(0, 1), units.map { it.speaker })
        assertEquals(listOf(0.0, 2.0), units.map { it.startSeconds })
    }

    @Test
    fun mergesSmallGapsAndSplitsAtTwentyEightSeconds() {
        val units = TranscriptionSegmentPlanner.makeUnits(
            speech = listOf(
                SpeechInterval(0.0, 20.0),
                SpeechInterval(20.1, 65.0),
            ),
            speakerTurns = emptyList(),
            audioDurationSeconds = 65.0,
        )

        assertEquals(3, units.size)
        assertTrue(units.all { it.endSeconds - it.startSeconds <= 28.0 })
        assertEquals(0.0, units.first().startSeconds, 0.0001)
        assertEquals(65.0, units.last().endSeconds, 0.0001)
    }

    @Test
    fun dropsIntervalsShorterThanProductionMinimum() {
        val units = TranscriptionSegmentPlanner.makeUnits(
            speech = listOf(SpeechInterval(0.0, 0.17), SpeechInterval(1.0, 1.2)),
            speakerTurns = emptyList(),
            audioDurationSeconds = 2.0,
        )

        assertEquals(1, units.size)
        assertEquals(1.0, units.single().startSeconds, 0.0001)
    }
}
