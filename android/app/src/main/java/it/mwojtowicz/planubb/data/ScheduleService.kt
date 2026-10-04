package it.mwojtowicz.planubb.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Instant

/** Download failures the app explains to the user (see `userMessage` in the UI). */
sealed class ScheduleException(message: String) : IOException(message) {
    class BadResponse(val code: Int) : ScheduleException("The plan server responded with HTTP $code.")
    class NotACalendar : ScheduleException("The plan server did not return a calendar.")
}

private const val BASE = "https://plany.ubb.edu.pl/"

/** GET relative to plany.ubb.edu.pl, returning the body as UTF-8 text. */
internal suspend fun httpGet(path: String, query: Map<String, Any> = emptyMap()): String = withContext(Dispatchers.IO) {
    val qs = query.entries.sortedBy { it.key }
        .joinToString("&") { "${it.key}=${URLEncoder.encode(it.value.toString(), "UTF-8")}" }
    val url = URL(BASE + path + if (qs.isEmpty()) "" else "?$qs")
    val conn = url.openConnection() as HttpURLConnection
    conn.connectTimeout = 20_000
    conn.readTimeout = 20_000
    conn.useCaches = false
    try {
        val code = conn.responseCode
        if (code !in 200..299) throw ScheduleException.BadResponse(code)
        conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
    } finally {
        conn.disconnect()
    }
}

/**
 * Downloads a plan from plany.ubb.edu.pl.
 *
 * Events come from the ICS exports (whole semester, abbreviated names). Full subject names are taken
 * from the legend on the weekly HTML pages, full teacher names from each teacher's own plan page.
 * Name lookups are cached in [NameDirectory].
 */
class ScheduleService {
    suspend fun fetch(source: PlanSource, directory: NameDirectory): Pair<ScheduleSnapshot, NameDirectory> = coroutineScope {
        val icsText = async { plan(mapOf("type" to source.type, "id" to source.id, "cvsfile" to "true")) }
        val mainHtml = async { runCatching { plan(pageQuery(source.type, source.id)) }.getOrNull() }

        val ics = icsText.await()
        if ("BEGIN:VCALENDAR" !in ics) {
            throw ScheduleException.NotACalendar()
        }

        // The HTML page only adds names; a failure there must not lose the schedule.
        val mainPage = mainHtml.await()?.let(PlanHtmlParser::parse) ?: PlanPage()
        directory.merge(mainPage)

        // The export only has the classes held in the current week's pattern: in an odd week,
        // classes held in even weeks only ("NZ-P") are missing. The export for each other week
        // fills them in.
        val weekExports = mainPage.weeks.map { it.id }.filter { it != mainPage.selectedWeekId }.map { id ->
            async {
                runCatching { IcsParser.parse(plan(mapOf("type" to source.type, "id" to source.id, "cvsfile" to "true", "w" to id))) }
                    .getOrNull()
            }
        }.awaitAll().filterNotNull()
        val rawEvents = IcsParser.merge(listOf(IcsParser.parse(ics)) + weekExports)

        // Weekly pages for weeks containing subjects/teachers we can't name yet.
        val weekIds = mainPage.weeks.associate { it.mondayKey to it.id }
        val weeksToFetch = mutableSetOf<Int>()
        for (raw in rawEvents) {
            val parsed = SummaryParser.parse(raw.summary, directory.rooms, directory.teacherIds.keys)
            val missing = directory.subjects[parsed.subjectCode] == null ||
                parsed.teacherCodes.any { directory.teacherIds[it] == null }
            val id = weekIds[PlanHtmlParser.mondayKey(raw.start)]
            if (missing && id != null && id != mainPage.selectedWeekId) weeksToFetch += id
        }
        weeksToFetch.map { id ->
            async { runCatching { PlanHtmlParser.parse(plan(pageQuery(source.type, source.id, week = id))) }.getOrNull() }
        }.awaitAll().filterNotNull().forEach(directory::merge)

        // Teacher full names.
        val knownTeachers = directory.teacherIds.keys.toSet()
        val teacherCodes = rawEvents.flatMap {
            SummaryParser.parse(it.summary, directory.rooms, knownTeachers).teacherCodes
        }.toSet()
        teacherCodes.filter { directory.teachers[it] == null }
            .mapNotNull { code -> directory.teacherIds[code]?.let { code to it } }
            .map { (code, id) ->
                async { runCatching { PlanHtmlParser.planName(plan(pageQuery(10, id))) }.getOrNull()?.let { code to it } }
            }
            .awaitAll().filterNotNull()
            .forEach { (code, name) -> directory.teachers[code] = name }

        val events = rawEvents.map { raw ->
            val p = SummaryParser.parse(raw.summary, directory.rooms, knownTeachers)
            ClassEvent(
                id = "${raw.start.epochSecond}-${raw.summary}",
                start = raw.start,
                end = raw.end,
                subjectCode = p.subjectCode,
                subjectName = directory.subjects[p.subjectCode] ?: p.subjectCode,
                kindCode = p.kindCode,
                teacherCodes = p.teacherCodes,
                teachers = p.teacherCodes.map { directory.teachers[it] ?: it },
                rooms = p.rooms,
            )
        }
        ScheduleSnapshot(source, mainPage.planName, Instant.now(), events) to directory
    }

    // Without winW/winH the server returns a JS stub that measures the window.
    private fun pageQuery(type: Int, id: Int, week: Int? = null): Map<String, Any> = buildMap {
        put("type", type); put("id", id); put("winW", 1319); put("winH", 795); put("loadBG", "000000")
        if (week != null) put("w", week)
    }

    private suspend fun plan(query: Map<String, Any>) = httpGet("plan.php", query)
}

/** Fetches levels of the group tree, one request per level, as the site's left frame does. */
class PlanTreeService {
    /** The departments (`parent == null`) or the children of [parent]. */
    suspend fun children(parent: PlanTreeNode?): List<PlanTreeNode> {
        if (parent == null) return PlanTreeParser.roots(httpGet("left_menu.php"))
        val branch = parent.branchId ?: return emptyList()
        val html = httpGet("left_menu_feed.php", mapOf("type" to 1, "branch" to branch, "link" to 0, "bOne" to 1))
        return PlanTreeParser.children(html)
    }
}
