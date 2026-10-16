package com.rivendell.stayword.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class RecordingValidationTest {
    @Test
    fun namesAreTrimmedAndBounded() {
        assertEquals("Meeting", RecordingNameValidator.validate("  Meeting  "))
        assertThrows(IllegalArgumentException::class.java) { RecordingNameValidator.validate("   ") }
        assertThrows(IllegalArgumentException::class.java) { RecordingNameValidator.validate("x".repeat(161)) }
    }

    @Test
    fun searchWildcardsAreTreatedAsLiteralText() {
        assertEquals("100\\%", "100%".escapeLikePattern())
        assertEquals("a\\_b", "a_b".escapeLikePattern())
        assertEquals("a\\\\b", "a\\b".escapeLikePattern())
    }
}
