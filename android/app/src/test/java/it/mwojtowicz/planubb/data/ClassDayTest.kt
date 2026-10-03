package it.mwojtowicz.planubb.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime

class ClassDayTest {
    private fun at(h: Int, m: Int): Instant = LocalDateTime.of(2026, 10, 3, 0, 0).atZone(Warsaw).toInstant()
        .plus(Duration.ofHours(h.toLong()).plusMinutes(m.toLong()))

    private fun event(h: Int, m: Int, minutes: Long, code: String) = ClassEvent(
        code, at(h, m), at(h, m).plus(Duration.ofMinutes(minutes)), code, code, "wyk", emptyList(), emptyList(), emptyList(),
    )

    private val snapshot = ScheduleSnapshot(
        PlanSource.Default, null, at(0, 0),
        listOf(event(8, 0, 90, "A"), event(9, 45, 90, "B"), event(24 + 10, 0, 30, "Tomorrow")),
    )

    @Test fun phasesThroughTheDay() {
        val day = ClassDay.of(snapshot, at(7, 0), Warsaw)!!
        assertEquals(listOf("A", "B"), day.classes.map { it.subjectCode })
        assertEquals(at(8, 0), day.start)
        assertEquals(at(11, 15), day.end)

        assertEquals(ClassDay.Phase.Waiting(day.classes[0], null), day.phase(at(7, 0)))
        assertEquals(ClassDay.Phase.InClass(day.classes[0], day.classes[1]), day.phase(at(8, 30)))
        assertEquals(ClassDay.Phase.Waiting(day.classes[1], at(9, 30)), day.phase(at(9, 35)))
        assertEquals(ClassDay.Phase.InClass(day.classes[1], null), day.phase(at(10, 0)))
        assertEquals(ClassDay.Phase.Done, day.phase(at(12, 0)))
    }

    @Test fun liveFromFirstClassToLastClass() {
        val day = ClassDay.of(snapshot, at(7, 0), Warsaw)!!
        assertFalse(day.isLive(at(7, 59)))
        assertTrue(day.isLive(at(8, 0)))
        assertTrue(day.isLive(at(9, 35)))  // the break between classes
        assertTrue(day.isLive(at(11, 14)))
        assertFalse(day.isLive(at(11, 15)))
    }

    @Test fun boundaries() {
        val day = ClassDay.of(snapshot, at(7, 0), Warsaw)!!
        assertEquals(at(9, 30), day.nextBoundary(at(8, 30)))
        assertNull(day.nextBoundary(at(11, 15)))
        assertNull(ClassDay.of(snapshot, at(11, 15), Warsaw))
    }
}
