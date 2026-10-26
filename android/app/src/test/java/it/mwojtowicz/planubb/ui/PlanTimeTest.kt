package it.mwojtowicz.planubb.ui

import it.mwojtowicz.planubb.data.localDate
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.util.Locale
import java.util.TimeZone

/** Classes are shown in Polish time, where they are held, on a device set to another time zone. */
class PlanTimeTest {
    private lateinit var zone: TimeZone
    private lateinit var locale: Locale

    @Before fun moveAbroad() {
        zone = TimeZone.getDefault()
        locale = Locale.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
        Locale.setDefault(Locale.forLanguageTag("pl-PL"))
    }

    @After fun comeBack() {
        TimeZone.setDefault(zone)
        Locale.setDefault(locale)
    }

    @Test fun timeIsPolish() {
        // 11:15 UTC is 13:15 in Warsaw (CEST) and 4:15 in Los Angeles.
        assertEquals("13:15", Instant.parse("2026-10-03T11:15:00Z").time())
    }

    @Test fun dayIsPolish() {
        // 23:30 UTC on Saturday is already Sunday 01:30 in Warsaw.
        assertEquals(LocalDate.of(2026, 10, 4), Instant.parse("2026-10-03T23:30:00Z").localDate())
    }
}
