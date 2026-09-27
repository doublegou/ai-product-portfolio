package com.rivendell.stayword.processing

data class SpeechInterval(val startSeconds: Double, val endSeconds: Double)
data class SpeakerTurn(val startSeconds: Double, val endSeconds: Double, val speaker: Int)
data class TranscriptionUnit(val startSeconds: Double, val endSeconds: Double, val speaker: Int?)

object TranscriptionSegmentPlanner {
    private const val MINIMUM_UNIT_DURATION = 0.18
    private const val MERGE_GAP = 0.20
    private const val MAXIMUM_UNIT_DURATION = 28.0

    fun makeUnits(
        speech: List<SpeechInterval>,
        speakerTurns: List<SpeakerTurn>,
        audioDurationSeconds: Double,
    ): List<TranscriptionUnit> {
        val duration = audioDurationSeconds.coerceAtLeast(0.0)
        val atoms = buildList {
            speech.sortedBy { it.startSeconds }.forEach { interval ->
                val start = interval.startSeconds.coerceIn(0.0, duration)
                val end = interval.endSeconds.coerceIn(start, duration)
                if (end - start < MINIMUM_UNIT_DURATION) return@forEach
                val overlaps = speakerTurns.filter {
                    it.endSeconds > start && it.startSeconds < end
                }
                val boundaries = buildSet {
                    add(start)
                    add(end)
                    overlaps.forEach { turn ->
                        add(turn.startSeconds.coerceIn(start, end))
                        add(turn.endSeconds.coerceIn(start, end))
                    }
                }.sorted()
                boundaries.zipWithNext().forEach { (atomStart, atomEnd) ->
                    if (atomEnd - atomStart >= MINIMUM_UNIT_DURATION) {
                        add(
                            TranscriptionUnit(
                                atomStart,
                                atomEnd,
                                dominantSpeaker(atomStart, atomEnd, overlaps),
                            ),
                        )
                    }
                }
            }
        }
        return normalizeSpeakers(mergeAdjacent(atoms).flatMap(::splitLongUnit))
    }

    private fun dominantSpeaker(start: Double, end: Double, turns: List<SpeakerTurn>): Int? =
        turns.map { turn ->
            turn.speaker to (minOf(end, turn.endSeconds) - maxOf(start, turn.startSeconds)).coerceAtLeast(0.0)
        }.filter { it.second > 0.0 }
            .maxWithOrNull(compareBy<Pair<Int, Double>> { it.second }.thenByDescending { it.first })
            ?.first

    private fun mergeAdjacent(units: List<TranscriptionUnit>): List<TranscriptionUnit> {
        val result = mutableListOf<TranscriptionUnit>()
        units.sortedBy { it.startSeconds }.forEach { unit ->
            val previous = result.lastOrNull()
            if (previous != null &&
                previous.speaker == unit.speaker &&
                unit.startSeconds - previous.endSeconds <= MERGE_GAP &&
                unit.endSeconds - previous.startSeconds <= MAXIMUM_UNIT_DURATION
            ) {
                result[result.lastIndex] = previous.copy(endSeconds = maxOf(previous.endSeconds, unit.endSeconds))
            } else {
                result += unit
            }
        }
        return result
    }

    private fun splitLongUnit(unit: TranscriptionUnit): List<TranscriptionUnit> {
        if (unit.endSeconds - unit.startSeconds <= MAXIMUM_UNIT_DURATION) return listOf(unit)
        return buildList {
            var start = unit.startSeconds
            while (start < unit.endSeconds) {
                val end = minOf(start + MAXIMUM_UNIT_DURATION, unit.endSeconds)
                if (end - start >= MINIMUM_UNIT_DURATION) add(unit.copy(startSeconds = start, endSeconds = end))
                start = end
            }
        }
    }

    private fun normalizeSpeakers(units: List<TranscriptionUnit>): List<TranscriptionUnit> {
        val mapping = linkedMapOf<Int, Int>()
        return units.map { unit ->
            unit.copy(speaker = unit.speaker?.let { mapping.getOrPut(it) { mapping.size } })
        }
    }
}
