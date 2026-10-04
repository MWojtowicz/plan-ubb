package it.mwojtowicz.planubb.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.LocalDateTime

/** Fixtures are real responses captured from plany.ubb.edu.pl (plan id 142113, Oct 2026), shared with the iOS tests. */
class ParserTest {
    private fun fixture(name: String): String =
        requireNotNull(javaClass.classLoader?.getResource(name)) { "Missing fixture $name" }.readText()

    @Test fun icsParsesWholeSemester() {
        val events = IcsParser.parse(fixture("plan.ics"))
        assertEquals(96, events.size)
        assertEquals(events.sortedBy { it.start }, events)

        val first = events.first { it.summary == "Ak wyk MaBe L136" }
        // DTSTART:20261003T060000Z → 08:00 in Warsaw (CEST)
        assertEquals(LocalDateTime.of(2026, 10, 3, 8, 0), LocalDateTime.ofInstant(first.start, Warsaw))
        assertEquals(Duration.ofMinutes(90), Duration.between(first.start, first.end))
    }

    /** plan.ics is the export for an odd week (no `w`); plan_week790.ics the one for an even week.
     *  Each lacks the classes of the other parity; together they make the whole plan. */
    @Test fun icsExportsOfDifferentWeeksMerge() {
        val odd = IcsParser.parse(fixture("plan.ics"))
        val even = IcsParser.parse(fixture("plan_week790.ics"))
        assertTrue(odd.none { it.summary.startsWith("Mn lab") })
        assertTrue(even.none { it.summary.startsWith("Ak ") })

        val merged = IcsParser.merge(listOf(odd, even))
        assertEquals(100, merged.size)
        assertEquals(4, merged.count { it.summary == "Mn lab JMr B316" })
        assertEquals(8, merged.count { it.summary.startsWith("Ak ") })
        assertEquals(merged.sortedBy { it.start }, merged)
    }

    @Test fun summaryWithMultipleTeachersAndRooms() {
        val p = SummaryParser.parse("JaI lek BGó ASzw L334A L324A")
        assertEquals("JaI", p.subjectCode)
        assertEquals("lek", p.kindCode)
        assertEquals(listOf("BGó", "ASzw"), p.teacherCodes)
        assertEquals(listOf("L334A", "L324A"), p.rooms)
    }

    @Test fun summaryUsesKnownCodes() {
        val p = SummaryParser.parse("MdI ćw WWi L136", knownRooms = setOf("L136"), knownTeachers = setOf("WWi"))
        assertEquals("ćw", p.kindCode)
        assertEquals(listOf("WWi"), p.teacherCodes)
        assertEquals(listOf("L136"), p.rooms)
    }

    @Test fun weekPage() {
        val page = PlanHtmlParser.parse(fixture("week.html"))
        assertEquals("Inf/NZ/Ist/3sem/1gr/b", page.planName)
        assertEquals("Architektura komputerów", page.subjects["Ak"])
        assertEquals("Systemy operacyjne II", page.subjects["SoII"])
        assertEquals(8, page.subjects.size)
        assertEquals(91148, page.teacherIds["ANo"])
        assertEquals(7144, page.teacherIds["ASzw"])
        assertTrue("L334A" in page.roomCodes)
        assertEquals(788, page.selectedWeekId)
        assertTrue(WeekOption(788, "2026-09-28") in page.weeks)
        assertTrue(WeekOption(802, "2027-01-04") in page.weeks)
    }

    @Test fun teacherPageName() {
        assertEquals("prof. UBB dr hab. inż. Andrzej Nowak", PlanHtmlParser.planName(fixture("teacher.html")))
    }

    @Test fun mondayKeyMatchesWeekOptions() {
        val first = IcsParser.parse(fixture("plan.ics")).first()
        assertEquals("2026-09-28", PlanHtmlParser.mondayKey(first.start))
    }

    @Test fun planSourceFromUrl() {
        assertEquals(PlanSource(0, 142113), PlanSource.parse("https://plany.ubb.edu.pl/plan.php?type=0&id=142113&winW=1319&winH=795&loadBG=000000"))
        assertEquals(PlanSource(0, 91148), PlanSource.parse(" 91148 "))
        assertEquals(PlanSource(10, 91148), PlanSource.parse("https://plany.ubb.edu.pl/plan.php?type=10&id=91148"))
        assertNull(PlanSource.parse("hello"))
    }

    @Test fun groupTreeRoots() {
        val roots = PlanTreeParser.roots(fixture("left_menu.html"))
        assertEquals(5, roots.size)
        assertEquals(PlanTreeNode(6153, "Wydział Budowy Maszyn i Informatyki"), roots.first())
        assertTrue(roots.any { it.name == "Wydział Inżynierii Materiałów, Budownictwa i Środowiska" })
    }

    @Test fun groupTreeLevels() {
        val courses = PlanTreeParser.children(fixture("tree_courses.html"))
        assertEquals(listOf("Cyberbezpieczeństwo NZ", "Informatyka NZ", "Sztuczna inteligencja NZ", "Zarządzanie i inżynieria produkcji NZ"), courses.map { it.name })
        assertEquals(6970, courses[1].branchId)
        assertNull(courses[1].plan)

        // Groups expand further and are plans themselves.
        val groups = PlanTreeParser.children(fixture("tree_groups.html"))
        assertEquals(listOf(
            PlanTreeNode(110206, "Inf/NZ/Ist/3sem/1gr", PlanSource(2, 110206)),
            PlanTreeNode(112225, "Inf/NZ/Ist/3sem/2gr", PlanSource(2, 112225)),
        ), groups)
        assertEquals(listOf("Group 1", "Group 2"), groups.map { it.shortName(groups) })

        val subgroups = PlanTreeParser.children(fixture("tree_subgroups.html"))
        assertEquals(listOf(PlanSource(0, 8145), PlanSource(0, 142113)), subgroups.map { it.plan })
        assertTrue(subgroups.all { it.isLeaf })
        assertEquals(listOf("Subgroup a", "Subgroup b"), subgroups.map { it.shortName(subgroups) })
    }

    @Test fun groupTreeShortNames() {
        fun node(name: String) = PlanTreeNode(1, name)
        val semesters = listOf(node("Inf/NZ/Ist/1sem"), node("Inf/NZ/Ist/2sem"))
        assertEquals(listOf("Semester 1", "Semester 2"), semesters.map { it.shortName(semesters) })
        val degrees = listOf(node("Inf/NZ/ I stopień"), node("Inf/NZ/ II stopień"))
        assertEquals(listOf("I stopień", "II stopień"), degrees.map { it.shortName(degrees) })
        val only = node("Inf/NZ/Ist/3sem/1gr")
        assertEquals("Group 1", only.shortName(listOf(only)))
        assertEquals("Stacjonarne", node("Stacjonarne").shortName(listOf(node("Stacjonarne"), node("Niestacjonarne Zaoczne"))))
    }

    @Test fun snapshotRoundTripsThroughJson() {
        val events = IcsParser.parse(fixture("plan.ics")).take(3).map {
            ClassEvent(it.summary, it.start, it.end, "Ak", "Architektura", "wyk", listOf("MaBe"), listOf("dr X"), listOf("L136"))
        }
        val snapshot = ScheduleSnapshot(PlanSource.Default, "Inf", events.first().start, events)
        val json = kotlinx.serialization.json.Json.encodeToString(ScheduleSnapshot.serializer(), snapshot)
        assertEquals(snapshot, kotlinx.serialization.json.Json.decodeFromString(ScheduleSnapshot.serializer(), json))
        assertNotNull(snapshot.current(events.first().start))
    }
}
