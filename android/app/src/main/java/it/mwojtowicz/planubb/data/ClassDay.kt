package it.mwojtowicz.planubb.data

import java.time.Instant
import java.time.ZoneId

/**
 * Today's classes, as shown by the live notification: whether a class is running, it's a break,
 * or the day is over, and when that changes next.
 */
data class ClassDay(
    /** Sorted by start. */
    val classes: List<ClassEvent>,
) {
    sealed interface Phase {
        data class InClass(val event: ClassEvent, val next: ClassEvent?) : Phase
        /** [since] is the end of the previous class, or null before the first one. */
        data class Waiting(val next: ClassEvent, val since: Instant?) : Phase
        data object Done : Phase
    }

    fun phase(at: Instant): Phase {
        val i = classes.indexOfFirst { it.isRunning(at) }
        if (i >= 0) return Phase.InClass(classes[i], classes.getOrNull(i + 1))
        val next = classes.firstOrNull { it.start.isAfter(at) } ?: return Phase.Done
        return Phase.Waiting(next, classes.lastOrNull { !it.end.isAfter(at) }?.end)
    }

    /** The next moment the notification needs to change: a class starting or ending. */
    fun nextBoundary(after: Instant): Instant? =
        classes.flatMap { listOf(it.start, it.end) }.filter { it.isAfter(after) }.minOrNull()

    val start: Instant? get() = classes.firstOrNull()?.start
    val end: Instant? get() = classes.maxOfOrNull { it.end }

    /** Whether the live notification is up: from the start of the first class to the end of the last one. */
    fun isLive(at: Instant): Boolean {
        val start = start ?: return false
        val end = end ?: return false
        return !at.isBefore(start) && at.isBefore(end)
    }

    companion object {
        /** The classes of the day containing [at], or null once they're all over. */
        fun of(snapshot: ScheduleSnapshot, at: Instant, zone: ZoneId = ZoneId.systemDefault()): ClassDay? {
            val day = at.localDate(zone)
            val classes = snapshot.events(day.startInstant(zone), day.plusDays(1).startInstant(zone))
            return if (classes.any { it.end.isAfter(at) }) ClassDay(classes) else null
        }
    }
}
