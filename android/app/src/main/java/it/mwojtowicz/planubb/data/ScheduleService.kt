package it.mwojtowicz.planubb.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLEncoder
import java.net.UnknownHostException
import java.time.Instant
import javax.net.ssl.SSLException

/** Download failures the app explains to the user (see `userMessage` in the UI). */
sealed class ScheduleException(message: String) : IOException(message) {
    class BadResponse(val code: Int) : ScheduleException("The plan server responded with HTTP $code.")
    class NotACalendar : ScheduleException("The plan server did not return a calendar.")
}

private const val BASE = "https://plany.ubb.edu.pl/"

/**
 * GET relative to plany.ubb.edu.pl, returning the body as UTF-8 text. The plan server is sometimes slow or
 * briefly unavailable (more so from abroad), so timeouts, dropped connections and 5xx/429 responses are
 * retried after 1 s and 2 s.
 */
internal suspend fun httpGet(path: String, query: Map<String, Any> = emptyMap(), attempts: Int = 3): String {
    var attempt = 1
    while (true) {
        try {
            return httpGetOnce(path, query)
        } catch (e: IOException) {
            if (attempt >= attempts || !e.isTransient) throw e
            delay(1_000L * attempt)
            attempt++
        }
    }
}

private val IOException.isTransient: Boolean
    get() = when (this) {
        is ScheduleException.BadResponse -> code == 429 || code >= 500
        is SocketTimeoutException, is SocketException, is UnknownHostException, is SSLException -> true
        else -> false
    }

private suspend fun httpGetOnce(path: String, query: Map<String, Any>): String = withContext(Dispatchers.IO) {
    val qs = query.entries.sortedBy { it.key }
        .joinToString("&") { "${it.key}=${URLEncoder.encode(it.value.toString(), "UTF-8")}" }
    val url = URL(BASE + path + if (qs.isEmpty()) "" else "?$qs")
    val conn = url.openConnection() as HttpURLConnection
    conn.connectTimeout = 30_000
    conn.readTimeout = 30_000
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
class ScheduleService(
    private val get: suspend (path: String, query: Map<String, Any>) -> String = { path, query -> httpGet(path, query) },
) {
    /** At most this many downloads at a time, so a slow server isn't flooded. */
    private val limit = Semaphore(4)

    suspend fun fetch(source: PlanSource, directory: NameDirectory): Pair<ScheduleSnapshot, NameDirectory> = coroutineScope {
        val icsText = async { plan(mapOf("type" to source.type, "id" to source.id, "cvsfile" to "true")) }
        val mainHtml = async { runCatching { plan(pageQuery(source.type, source.id)) } }

        // In a week without classes the export is the plan's "Brak zajęć" HTML page instead of a
        // calendar. That page still names the plan and lists the semester's weeks; for a wrong plan id
        // the name is empty.
        val ics = icsText.await()
        val emptyWeekPage = if ("BEGIN:VCALENDAR" in ics) null else PlanHtmlParser.parse(ics)
        if (emptyWeekPage != null && emptyWeekPage.planName == null) throw ScheduleException.NotACalendar()

        // The HTML page adds names, and the week list when the export had none to give; a failure
        // there must not lose the classes.
        val mainResult = mainHtml.await()
        val mainPage = mainResult.getOrNull()?.let(PlanHtmlParser::parse) ?: PlanPage()
        directory.merge(mainPage)
        val weekList = if (mainPage.weeks.isEmpty()) emptyWeekPage ?: mainPage else mainPage

        // The export only has the classes held in the current week's pattern: in an odd week,
        // classes held in even weeks only ("NZ-P") are missing, and in a week without classes
        // there are none. The export for each other week fills them in.
        val weekExports = weekList.weeks.map { it.id }.filter { it != weekList.selectedWeekId }.map { id ->
            async { runCatching { IcsParser.parse(plan(mapOf("type" to source.type, "id" to source.id, "cvsfile" to "true", "w" to id))) } }
        }.awaitAll()
        val rawEvents = IcsParser.merge(listOf(IcsParser.parse(ics)) + weekExports.mapNotNull { it.getOrNull() })

        // No classes at all is a real answer (an even semester in autumn has none yet), but only
        // when every week was checked. Otherwise report what went wrong.
        if (rawEvents.isEmpty()) {
            weekExports.firstNotNullOfOrNull { it.exceptionOrNull() }?.let { throw it }
            if (weekList.weeks.isEmpty()) mainResult.exceptionOrNull()?.let { throw it }
        }

        // Weekly pages for weeks containing subjects/teachers we can't name yet.
        val weekIds = weekList.weeks.associate { it.mondayKey to it.id }
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
        ScheduleSnapshot(source, mainPage.planName ?: emptyWeekPage?.planName, Instant.now(), events) to directory
    }

    // Without winW/winH the server returns a JS stub that measures the window.
    private fun pageQuery(type: Int, id: Int, week: Int? = null): Map<String, Any> = buildMap {
        put("type", type); put("id", id); put("winW", 1319); put("winH", 795); put("loadBG", "000000")
        if (week != null) put("w", week)
    }

    private suspend fun plan(query: Map<String, Any>) = limit.withPermit { get("plan.php", query) }
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
