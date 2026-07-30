package com.rivendell.stayword.util

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

class FormattersTest {
    @Test
    fun durationUsesMinuteFormatBelowOneHour() {
        Locale.setDefault(Locale.US)
        assertEquals("0:00", formatDuration(-1))
        assertEquals("1:05", formatDuration(65_999))
        assertEquals("59:59", formatDuration(3_599_999))
    }

    @Test
    fun durationUsesHourFormatAtOneHour() {
        Locale.setDefault(Locale.US)
        assertEquals("1:00:00", formatDuration(3_600_000))
        assertEquals("12:34:56", formatDuration(45_296_000))
    }
}
