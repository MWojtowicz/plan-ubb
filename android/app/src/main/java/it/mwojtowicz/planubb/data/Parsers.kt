package it.mwojtowicz.planubb.data

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

// region ICS

data class RawIcsEvent(val start: Instant, val end: Instant, val summary: String)

object IcsParser {
    private val utcFormat = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
    private val localFormat = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss")
    private val dateFormat = DateTimeFormatter.ofPattern("yyyyMMdd")

    private class Field(val params: Map<String, String>, val value: String)

    fun parse(text: String): List<RawIcsEvent> {
        val events = mutableListOf<RawIcsEvent>()
        var fields: MutableMap<String, Field>? = null

        for (line in unfoldedLines(text)) {
            if (line == "BEGIN:VEVENT") {
                fields = mutableMapOf()
                continue
            }
            if (line == "END:VEVENT") {
                val f = fields
                val start = f?.get("DTSTART")?.let { parseDate(it.value, it.params) }
                val end = f?.get("DTEND")?.let { parseDate(it.value, it.params) }
                if (start != null && end != null) {
                    events += RawIcsEvent(start, end, unescape(f["SUMMARY"]?.value ?: ""))
                }
                fields = null
                continue
            }
            val colon = line.indexOf(':')
            if (fields == null || colon < 0) continue
            val head = line.substring(0, colon).split(";")
            val name = head.first().uppercase()
            val params = head.drop(1).mapNotNull {
                val kv = it.split("=", limit = 2)
                if (kv.size == 2) kv[0].uppercase() to kv[1] else null
            }.toMap()
            fields[name] = Field(params, line.substring(colon + 1))
        }
        return events.sortedBy { it.start }
    }

    private fun unfoldedLines(text: String): List<String> {
        val lines = mutableListOf<String>()
        val normalized = text.replace("\r\n", "\n").replace("\r", "\n")
        for (raw in normalized.split("\n")) {
            if (raw.isEmpty()) continue
            if ((raw.startsWith(" ") || raw.startsWith("\t")) && lines.isNotEmpty()) {
                lines[lines.lastIndex] = lines.last() + raw.substring(1)
            } else {
                lines += raw
            }
        }
        return lines
    }

    fun parseDate(value: String, params: Map<String, String> = emptyMap()): Instant? = runCatching {
        when {
            value.endsWith("Z") -> LocalDateTime.parse(value, utcFormat).toInstant(ZoneOffset.UTC)
            "T" in value -> {
                val zone = params["TZID"]?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: Warsaw
                LocalDateTime.parse(value, localFormat).atZone(zone).toInstant()
            }
            else -> LocalDate.parse(value, dateFormat).atStartOfDay(Warsaw).toInstant()
        }
    }.getOrNull()

    private fun unescape(s: String): String = s
        .replace("\\n", " ")
        .replace("\\N", " ")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
}

// endregion

// region Summary ("Ak wyk MaBe L136", "JaI lek BGó ASzw L334A L324A")

data class ParsedSummary(
    val subjectCode: String,
    val kindCode: String,
    val teacherCodes: List<String>,
    val rooms: List<String>,
)

object SummaryParser {
    private val roomPattern = Regex("^[A-Z]{1,3}\\d+[A-Za-z]?$")

    fun parse(summary: String, knownRooms: Set<String> = emptySet(), knownTeachers: Set<String> = emptySet()): ParsedSummary {
        val tokens = summary.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val subject = tokens.firstOrNull() ?: return ParsedSummary("", "", emptyList(), emptyList())
        val teachers = mutableListOf<String>()
        val rooms = mutableListOf<String>()
        for (token in tokens.drop(2)) {
            when {
                token in knownTeachers -> teachers += token
                token in knownRooms || looksLikeRoom(token) -> rooms += token
                else -> teachers += token
            }
        }
        return ParsedSummary(subject, tokens.getOrElse(1) { "" }, teachers, rooms)
    }

    fun looksLikeRoom(token: String): Boolean = roomPattern.matches(token)
}

// endregion

// region HTML plan page

data class WeekOption(
    val id: Int,
    /** Monday of the week, as "yyyy-MM-dd" in Europe/Warsaw. */
    val mondayKey: String,
)

data class PlanPage(
    var planName: String? = null,
    var selectedWeekId: Int? = null,
    val weeks: MutableList<WeekOption> = mutableListOf(),
    val subjects: MutableMap<String, String> = mutableMapOf(),
    val teacherIds: MutableMap<String, Int> = mutableMapOf(),
    val roomCodes: MutableSet<String> = mutableSetOf(),
)

object PlanHtmlParser {
    fun parse(html: String): PlanPage {
        val page = PlanPage(planName = planName(html))

        for (m in matches("<strong>([^<]+)</strong>\\s*-\\s*([^<]+)", html)) {
            var name = m[2]
            name.indexOf(", występowanie:").takeIf { it >= 0 }?.let { name = name.substring(0, it) }
            page.subjects[decode(m[1]).trim()] = decode(name).trim()
        }
        for (m in matches("type=10&(?:amp;)?id=(\\d+)\"[^>]*>([^<]+)</a>", html)) {
            m[1].toIntOrNull()?.let { page.teacherIds[decode(m[2]).trim()] = it }
        }
        for (m in matches("type=20&(?:amp;)?id=\\d+\"[^>]*>([^<]+)</a>", html)) {
            page.roomCodes += decode(m[1]).trim()
        }

        // Week dropdown: <option value="788" selected>28.09-04.10
        val startYear = matches("rok (\\d{4})/(\\d{4})", html).firstOrNull()?.get(1)?.toIntOrNull()
        val selectStart = html.indexOf("id=\"wBWeek\"")
        if (startYear != null && selectStart >= 0) {
            val rest = html.substring(selectStart + "id=\"wBWeek\"".length)
            val select = rest.indexOf("</select>").let { if (it >= 0) rest.substring(0, it) else rest }
            for (m in matches("<option value=\"(\\d+)\"([^>]*)>\\s*(\\d{2})\\.(\\d{2})-\\d{2}\\.\\d{2}", select)) {
                val id = m[1].toIntOrNull() ?: continue
                val day = m[3].toIntOrNull() ?: continue
                val month = m[4].toIntOrNull() ?: continue
                // Academic year: Aug–Dec belong to the first year, Jan–Jul to the second.
                val year = if (month >= 8) startYear else startYear + 1
                page.weeks += WeekOption(id, "%04d-%02d-%02d".format(year, month, day))
                if ("selected" in m[2]) page.selectedWeekId = id
            }
        }
        return page
    }

    /** "Plan zajęć - prof. UBB dr hab. inż. Andrzej Nowak, tydzień 28.09-04.10, …" → the name part. */
    fun planName(html: String): String? =
        matches("Plan zajęć - (.+?), (?:liczba stanowisk|tydzień)", html).firstOrNull()?.let { decode(it[1]).trim() }

    fun mondayKey(instant: Instant): String = mondayOf(instant.localDate(Warsaw)).toString()

    fun decode(s: String): String = s
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&nbsp;", " ")
        .replace("&amp;", "&")

    private fun matches(pattern: String, text: String): List<List<String>> =
        Regex(pattern, RegexOption.DOT_MATCHES_ALL).findAll(text).map { m -> m.groupValues }.toList()
}

// endregion

// region Group tree (the site's left frame)

/**
 * One entry in the site's "Grupy" tree: department → study mode → course → degree → semester → group → subgroup.
 * Inner nodes from the semester down are plans themselves too (`plan.php?type=2`).
 */
/** How [PlanTreeNode.shortName] spells out semesters, groups and subgroups. */
class TreeLabels(val semester: (String) -> String, val group: (String) -> String, val subgroup: (String) -> String) {
    companion object {
        val English = TreeLabels({ "Semester $it" }, { "Group $it" }, { "Subgroup $it" })
    }
}

data class PlanTreeNode(
    /** The id to expand this node with, or null for a leaf. */
    val branchId: Int?,
    val name: String,
    /** The plan this node opens, if it links to one. */
    val plan: PlanSource? = null,
) {
    val key: String get() = branchId?.let { "b$it" } ?: plan?.let { "p${it.type}-${it.id}" } ?: name
    val isLeaf: Boolean get() = branchId == null

    /**
     * A short title for a list of siblings: drops the path they share and spells out the common patterns
     * ("Inf/NZ/Ist/3sem" → "Semester 3", "…/1gr" → "Group 1", "…/1gr/b" → "Subgroup b").
     */
    fun shortName(siblings: List<PlanTreeNode>, labels: TreeLabels = TreeLabels.English): String {
        val shared = if (siblings.size > 1) sharedPathPrefix(siblings.map { it.name }) else parentPath(name)
        val last = (if (shared.isEmpty()) name else name.drop(shared.length)).trim()
        Regex("(\\d+)\\s*sem").matchEntire(last)?.let { return labels.semester(it.groupValues[1]) }
        Regex("(\\d+)\\s*gr").matchEntire(last)?.let { return labels.group(it.groupValues[1]) }
        if (isLeaf && plan != null && last.length <= 2 && last != name) return labels.subgroup(last)
        return last.ifEmpty { name }
    }

    private companion object {
        /** The longest common prefix that ends with "/" (so whole path segments only). */
        fun sharedPathPrefix(names: List<String>): String {
            var prefix = names.firstOrNull() ?: return ""
            for (n in names.drop(1)) while (!n.startsWith(prefix)) prefix = prefix.dropLast(1)
            val slash = prefix.lastIndexOf('/')
            return if (slash < 0) "" else prefix.substring(0, slash + 1)
        }

        fun parentPath(name: String): String {
            val slash = name.lastIndexOf('/')
            return if (slash < 0 || slash == name.lastIndex) "" else name.substring(0, slash + 1)
        }
    }
}

object PlanTreeParser {
    /** Departments from `left_menu.php`: `branch(1,6153,0,'Wydział …')`. */
    fun roots(html: String): List<PlanTreeNode> =
        Regex("branch\\(1,\\s*(\\d+),\\s*\\d+,\\s*'([^']*)'\\)").findAll(html).mapNotNull { m ->
            m.groupValues[1].toIntOrNull()?.let { PlanTreeNode(it, PlanHtmlParser.decode(m.groupValues[2]).trim()) }
        }.toList()

    /**
     * One level from `left_menu_feed.php`: a flat `<ul>` of `<li>` items. Each item is either expandable
     * (`get_left_tree_branch( 'id', … )`) or a leaf, and its name is either plain text or a link to a plan.
     */
    fun children(html: String): List<PlanTreeNode> = html.split("<li").drop(1).mapNotNull { item ->
        val branch = Regex("get_left_tree_branch\\(\\s*'(\\d+)'").find(item)?.groupValues?.get(1)?.toIntOrNull()
        val link = Regex("href=\"plan\\.php\\?type=(\\d+)&(?:amp;)?id=(\\d+)\"[^>]*>([^<]+)</a>").find(item)
        if (link != null) {
            val (type, id, name) = link.destructured
            return@mapNotNull PlanTreeNode(branch, PlanHtmlParser.decode(name).trim(), PlanSource(type.toInt(), id.toInt()))
        }
        val text = Regex(">\\s*([^<>]+?)\\s*<div").find(item)?.groupValues?.get(1)
        if (branch == null || text == null) null else PlanTreeNode(branch, PlanHtmlParser.decode(text).trim())
    }
}

// endregion
