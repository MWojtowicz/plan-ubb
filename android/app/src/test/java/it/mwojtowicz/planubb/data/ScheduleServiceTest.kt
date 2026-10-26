package it.mwojtowicz.planubb.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.LocalDate

/**
 * Fixtures: plan 142113 in the week of 26.10 (no classes), whose export is the "Brak zajęć" page
 * (plan_empty_week.html); its odd and even weeks' exports (plan.ics, plan_week790.ics); and the page a
 * wrong plan id gets (plan_unknown.html).
 */
class ScheduleServiceTest {
    private fun fixture(name: String): String =
        requireNotNull(javaClass.classLoader?.getResource(name)) { "Missing fixture $name" }.readText()

    private val source = PlanSource(0, 142113)

    /** A server that answers with [handler]; null means 404. */
    private fun service(handler: (Map<String, Any>) -> String?) = ScheduleService { _, query ->
        handler(query) ?: throw ScheduleException.BadResponse(404)
    }

    /** What App Review saw: the current week has no classes and the plan page didn't load.
     *  The empty week's page still lists the weeks, so the other weeks' exports give the plan. */
    @Test fun emptyWeekWithoutPlanPage() = runBlocking {
        val empty = fixture("plan_empty_week.html")
        val odd = fixture("plan.ics")
        val even = fixture("plan_week790.ics")
        val (snapshot, _) = service { q ->
            when {
                "cvsfile" !in q -> null
                q["w"] == 790 -> even
                q["w"] == 793 -> odd
                else -> empty
            }
        }.fetch(source, NameDirectory())
        assertEquals(100, snapshot.events.size)
        assertEquals("Inf/NZ/Ist/3sem/1gr/b", snapshot.planName)
    }

    /** An even semester in autumn: the plan exists but has no classes in any week. */
    @Test fun planWithoutClassesIsNotAnError() = runBlocking {
        val empty = fixture("plan_empty_week.html")
        val (snapshot, _) = service { empty }.fetch(source, NameDirectory())
        assertTrue(snapshot.events.isEmpty())
        assertEquals("Inf/NZ/Ist/3sem/1gr/b", snapshot.planName)
    }

    @Test fun unknownPlan() = runBlocking {
        val unknown = fixture("plan_unknown.html")
        try {
            service { unknown }.fetch(PlanSource(0, 999999999), NameDirectory())
            fail("Expected an error")
        } catch (_: ScheduleException.NotACalendar) {
        }
    }

    /** When the other weeks can't be downloaded, the empty result says why instead of claiming the plan
     *  has no classes or a wrong URL. */
    @Test fun failedWeeksAreReported() = runBlocking {
        val empty = fixture("plan_empty_week.html")
        try {
            service { q -> if ("w" in q) null else empty }.fetch(source, NameDirectory())
            fail("Expected an error")
        } catch (e: ScheduleException.BadResponse) {
            assertEquals(404, e.code)
        }
    }

    /** An error or maintenance page sent with HTTP 200 is retried like a failed download. */
    @Test fun unexpectedPageIsRetried() = runBlocking {
        val odd = fixture("plan.ics")
        var exports = 0
        val (snapshot, _) = service { q ->
            if ("cvsfile" !in q) null else if (++exports == 1) "<html><body>Przerwa techniczna</body></html>" else odd
        }.fetch(source, NameDirectory())
        assertEquals(96, snapshot.events.size)
    }

    /** …and if it keeps coming, the error says so instead of blaming the plan URL. */
    @Test fun unexpectedPageIsReported() = runBlocking {
        try {
            service { "<html><body>Przerwa techniczna</body></html>" }.fetch(source, NameDirectory())
            fail("Expected an error")
        } catch (_: ScheduleException.UnexpectedResponse) {
        }
    }

    @Test fun unknownPlanHasNoName() {
        assertNull(PlanHtmlParser.planName(fixture("plan_unknown.html")))
        val page = PlanHtmlParser.parse(fixture("plan_empty_week.html"))
        assertEquals(792, page.selectedWeekId)
        assertEquals(19, page.weeks.size)
    }

    @Test fun studyTerms() {
        assertEquals(StudyTerm.WINTER, StudyTerm.usualFor("Inf/NZ/Ist/3sem/1gr/b"))
        assertEquals(StudyTerm.SUMMER, StudyTerm.usualFor("Inf/NZ/Ist/2sem"))
        assertEquals(StudyTerm.WINTER, StudyTerm.usualFor("Inf/NZ/IIst/1sem/1gr"))
        assertNull(StudyTerm.usualFor("prof. UBB dr hab. inż. Andrzej Nowak"))

        fun date(month: Int) = LocalDate.of(2026, month, 15).atStartOfDay(Warsaw).toInstant()
        assertEquals(StudyTerm.WINTER, StudyTerm.current(date(10)))
        assertEquals(StudyTerm.WINTER, StudyTerm.current(date(1)))
        assertEquals(StudyTerm.SUMMER, StudyTerm.current(date(3)))
        assertEquals(StudyTerm.WINTER, StudyTerm.current(date(8)))
    }
}
