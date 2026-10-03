package it.mwojtowicz.planubb.ui

import android.content.Context
import android.text.format.DateFormat
import it.mwojtowicz.planubb.R
import it.mwojtowicz.planubb.data.ClassEvent
import it.mwojtowicz.planubb.data.ScheduleException
import it.mwojtowicz.planubb.data.localDate
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.TemporalAccessor
import java.util.Locale

// Formatters are built on each call, so they follow the locale even after the user changes it.

/** The locale's own order and wording for the fields in [skeleton] ("EEEEdMMMM" → "Friday, October 3" / "piątek, 3 października"). */
fun TemporalAccessor.formatSkeleton(skeleton: String): String {
    val locale = Locale.getDefault()
    return DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, skeleton), locale).format(this)
}

fun Instant.time(): String =
    atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault()))

/** "14:30" today, "Sat 08:00" on other days. */
fun Instant.timeOrDayTime(today: LocalDate = LocalDate.now()): String =
    if (localDate() == today) time() else atZone(ZoneId.systemDefault()).formatSkeleton("EEEjmm")

fun ClassEvent.timeRange(context: Context): String = context.getString(R.string.time_range, start.time(), end.time())

fun LocalDate.daySectionTitle(context: Context, today: LocalDate = LocalDate.now()): String {
    val base = formatSkeleton("EEEEdMMMM")
    return when (this) {
        today -> context.getString(R.string.today_day, base)
        today.plusDays(1) -> context.getString(R.string.tomorrow_day, base)
        else -> base
    }
}

/** "1:02:03" or "42:17", like a countdown timer. */
fun Duration.countdown(): String {
    val s = seconds.coerceAtLeast(0)
    val h = s / 3600
    val m = (s % 3600) / 60
    val sec = s % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, sec) else "%d:%02d".format(m, sec)
}

/** Minutes past the full hour (`Duration.toMinutesPart` needs API 31). */
private val Duration.minutesPart: Int get() = (toMinutes() % 60).toInt()

/** "in 1 h 20 min", "in 5 min", "in 2 days". */
fun Duration.relative(context: Context): String = when {
    toDays() >= 2 -> context.resources.getQuantityString(R.plurals.in_days, toDays().toInt(), toDays().toInt())
    toHours() >= 1 ->
        if (minutesPart == 0) context.getString(R.string.in_hours, toHours().toInt())
        else context.getString(R.string.in_hours_minutes, toHours().toInt(), minutesPart)
    else -> context.getString(R.string.in_minutes, toMinutes().coerceAtLeast(1).toInt())
}

/** "1 h 30 min", "2 h", "45 min". */
fun Duration.length(context: Context): String = when {
    minutesPart == 0 -> context.getString(R.string.duration_hours, toHours().toInt())
    toHours() == 0L -> context.getString(R.string.duration_minutes, toMinutes().toInt())
    else -> context.getString(R.string.duration_hours_minutes, toHours().toInt(), minutesPart)
}

/** The kind of class in the user's language; unknown codes are shown as they are. */
fun ClassEvent.kindName(context: Context): String =
    ClassEvent.kindNameRes(kindCode)?.let(context::getString) ?: kindCode

/** A message for an error from downloading, in the user's language. */
fun Throwable.userMessage(context: Context, fallback: Int = R.string.error_download): String = when (this) {
    is ScheduleException.BadResponse -> context.getString(R.string.error_http, code)
    is ScheduleException.NotACalendar -> context.getString(R.string.error_not_calendar)
    is UnknownHostException, is ConnectException -> context.getString(R.string.error_offline)
    is SocketTimeoutException -> context.getString(R.string.error_timeout)
    else -> context.getString(fallback)
}

/** Groups events by calendar day, preserving order. */
fun groupedByDay(events: List<ClassEvent>): List<Pair<LocalDate, List<ClassEvent>>> =
    events.groupBy { it.start.localDate() }.toList()
