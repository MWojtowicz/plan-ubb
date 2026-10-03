package it.mwojtowicz.planubb.data

import androidx.annotation.StringRes
import it.mwojtowicz.planubb.R
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.net.URI
import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

/**
 * Identifies a plan on plany.ubb.edu.pl (`plan.php?type=…&id=…`).
 * type 0 = student group, 2 = semester/group aggregate, 10 = teacher, 20 = room.
 */
@Serializable
data class PlanSource(val type: Int, val id: Int) {
    val webUrl: String
        get() = "https://plany.ubb.edu.pl/plan.php?type=$type&id=$id&winW=1319&winH=795&loadBG=000000"

    companion object {
        val Default = PlanSource(type = 0, id = 142113)

        /** Accepts a full plan URL (as copied from the browser) or a bare numeric id. */
        fun parse(text: String): PlanSource? {
            val trimmed = text.trim()
            trimmed.toIntOrNull()?.let { return PlanSource(0, it) }
            val query = runCatching { URI(trimmed).rawQuery }.getOrNull() ?: return null
            val items = query.split("&").mapNotNull {
                val kv = it.split("=", limit = 2)
                if (kv.size == 2) kv[0] to kv[1] else null
            }.toMap()
            val id = items["id"]?.toIntOrNull() ?: return null
            return PlanSource(items["type"]?.toIntOrNull() ?: 0, id)
        }
    }
}

@Serializable
data class ClassEvent(
    val id: String,
    @Serializable(with = InstantSerializer::class) val start: Instant,
    @Serializable(with = InstantSerializer::class) val end: Instant,
    val subjectCode: String,
    val subjectName: String,
    val kindCode: String,
    val teacherCodes: List<String>,
    val teachers: List<String>,
    val rooms: List<String>,
) {
    val location: String get() = if (rooms.isEmpty()) "—" else rooms.joinToString(", ")
    val teacherNames: String get() = if (teachers.isEmpty()) "—" else teachers.joinToString(", ")
    val duration: Duration get() = Duration.between(start, end)

    fun isRunning(at: Instant): Boolean = !start.isAfter(at) && at.isBefore(end)

    companion object {
        /** The name of a class kind code, or null for codes the app doesn't know (shown as they are). */
        @StringRes
        fun kindNameRes(code: String): Int? = when (code.lowercase()) {
            "wyk" -> R.string.kind_lecture
            "lab" -> R.string.kind_laboratory
            "ćw", "cw" -> R.string.kind_exercises
            "lek" -> R.string.kind_language
            "proj", "pro" -> R.string.kind_project
            "sem" -> R.string.kind_seminar
            "wf" -> R.string.kind_pe
            "" -> R.string.kind_class
            else -> null
        }
    }
}

@Serializable
data class ScheduleSnapshot(
    val source: PlanSource,
    val planName: String? = null,
    @Serializable(with = InstantSerializer::class) val fetchedAt: Instant,
    /** Sorted by start. */
    val events: List<ClassEvent>,
) {
    fun current(at: Instant): ClassEvent? = events.firstOrNull { it.isRunning(at) }

    fun upcoming(after: Instant, limit: Int = Int.MAX_VALUE): List<ClassEvent> =
        events.asSequence().filter { it.start.isAfter(after) }.take(limit).toList()

    fun events(from: Instant, to: Instant): List<ClassEvent> =
        events.filter { !it.start.isBefore(from) && it.start.isBefore(to) }
}

/** Cache of abbreviation → full name lookups, so refreshes only scrape what's new. */
@Serializable
data class NameDirectory(
    val subjects: MutableMap<String, String> = mutableMapOf(),
    val teacherIds: MutableMap<String, Int> = mutableMapOf(),
    val teachers: MutableMap<String, String> = mutableMapOf(),
    val rooms: MutableSet<String> = mutableSetOf(),
) {
    fun merge(page: PlanPage) {
        subjects.putAll(page.subjects)
        teacherIds.putAll(page.teacherIds)
        rooms.addAll(page.roomCodes)
    }
}

object InstantSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("Instant", PrimitiveKind.LONG)
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeLong(value.toEpochMilli())
    override fun deserialize(decoder: Decoder): Instant = Instant.ofEpochMilli(decoder.decodeLong())
}

val Warsaw: ZoneId = ZoneId.of("Europe/Warsaw")

/** Monday of the week containing [date], as in the university plan. */
fun mondayOf(date: LocalDate): LocalDate = date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

fun Instant.localDate(zone: ZoneId = ZoneId.systemDefault()): LocalDate = atZone(zone).toLocalDate()

fun LocalDate.startInstant(zone: ZoneId = ZoneId.systemDefault()): Instant = atStartOfDay(zone).toInstant()
