package it.mwojtowicz.planubb.live

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.os.Build
import android.provider.Settings
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.core.graphics.drawable.IconCompat
import it.mwojtowicz.planubb.R
import it.mwojtowicz.planubb.data.ClassDay
import it.mwojtowicz.planubb.data.ClassEvent
import it.mwojtowicz.planubb.data.ScheduleStore
import it.mwojtowicz.planubb.data.localDate
import it.mwojtowicz.planubb.ui.MainActivity
import it.mwojtowicz.planubb.ui.kindArgb
import it.mwojtowicz.planubb.ui.kindName
import it.mwojtowicz.planubb.ui.time
import java.time.Duration
import java.time.Instant

/**
 * The Android counterpart of the iOS Live Activity: an ongoing notification for the day's classes,
 * up from the start of the first class to the end of the last one.
 *
 * It asks to be promoted to a "Live Update" (Android 16+), so it sits at the top of the lock screen and
 * shows a countdown chip in the status bar. On Android 17+ it uses [Notification.MetricStyle], laid out
 * like the iOS banner: a big countdown, the room and the next class. On Android 16 and older, its
 * progress bar is the day's timeline instead: a coloured segment per class, grey for the breaks.
 * The countdowns are drawn by the system, so they tick on their own; [PlanSync] refreshes the rest at
 * every class boundary and every few minutes.
 */
object LiveClassNotification {
    private const val CHANNEL = "live"
    private const val ID = 1
    /** How often the notification is redrawn while it's up (the timeline's progress). */
    val RefreshEvery: Duration = Duration.ofMinutes(5)

    fun canPost(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** Whether the system will show it as a Live Update (Android 16+, the user can turn it off per app). */
    fun canPromote(context: Context): Boolean =
        Build.VERSION.SDK_INT < 36 || context.getSystemService(NotificationManager::class.java).canPostPromotedNotifications()

    fun openPromotionSettings(context: Context) {
        val intent = if (Build.VERSION.SDK_INT >= 36) {
            Intent(Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS)
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        }
        context.startActivity(intent.putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Turns the live notification on or off (the button on Upcoming, the switch in Settings). */
    fun setEnabled(context: Context, on: Boolean) {
        ScheduleStore.get(context).liveUpdatesEnabled = on
        // Turning it on is a clear "show it": forget that it was swiped away today.
        if (on) context.getSharedPreferences("live", Context.MODE_PRIVATE).edit { remove("dismissedOn") }
        PlanSync.scheduleChanged(context)
    }

    /** Posts, updates or removes the notification. Returns true if it's showing. */
    fun update(context: Context, now: Instant = Instant.now()): Boolean {
        val store = ScheduleStore.get(context)
        val snapshot = store.snapshot.value
        val day = snapshot?.let { ClassDay.of(it, now) }
        val prefs = context.getSharedPreferences("live", Context.MODE_PRIVATE)
        val dismissedToday = prefs.getString("dismissedOn", null) == now.localDate().toString()
        if (!store.liveUpdatesEnabled || !store.hasChosenSource || day == null || dismissedToday || !day.isLive(now) || !canPost(context)) {
            cancel(context)
            return false
        }
        createChannel(context)
        val notification = if (Build.VERSION.SDK_INT >= 37) buildMetric(context, day, now) else buildTimeline(context, day, now)
        try {
            NotificationManagerCompat.from(context).notify(ID, notification)
        } catch (e: SecurityException) {
            return false
        }
        return true
    }

    fun cancel(context: Context) = NotificationManagerCompat.from(context).cancel(ID)

    /**
     * It was removed: if the user swiped it away during the class day, leave it gone until tomorrow.
     * The system also reports the removal at the end of the day (the timeout), which isn't the user's choice.
     */
    fun dismissedByUser(context: Context, now: Instant = Instant.now()) {
        val day = ScheduleStore.get(context).snapshot.value?.let { ClassDay.of(it, now) }
        if (day == null || !day.isLive(now)) return
        context.getSharedPreferences("live", Context.MODE_PRIVATE).edit {
            putString("dismissedOn", now.localDate().toString())
        }
    }

    /** What the notification is about at [now]: the running class, or the next one during a break. */
    private class Content(context: Context, day: ClassDay, now: Instant) {
        val phase = day.phase(now)
        val focus: ClassEvent = when (phase) {
            is ClassDay.Phase.InClass -> phase.event
            is ClassDay.Phase.Waiting -> phase.next
            ClassDay.Phase.Done -> error("not shown when done")
        }
        val inClass = phase is ClassDay.Phase.InClass
        /** When the countdown reaches zero: the end of the class, or the start of the next one. */
        val countdownTo: Instant = if (inClass) focus.end else focus.start
        /** "Now · Lecture", "Break", like the caption of the iOS banner. */
        val header: String = when (phase) {
            is ClassDay.Phase.InClass -> context.getString(R.string.live_header_now, focus.kindName(context))
            is ClassDay.Phase.Waiting -> context.getString(if (phase.since == null) R.string.notif_first_class else R.string.notif_break)
            ClassDay.Phase.Done -> ""
        }
        val upNext: ClassEvent? = (phase as? ClassDay.Phase.InClass)?.next
    }

    /**
     * Android 17+: big metrics, like the iOS banner. A countdown (also shown in the status bar chip), the room,
     * and where the next class is, with its time in the label ("→ 11:30" over "L412"). A time as the
     * big value gets cut off when the clock is 12-hour ("11:30 …"), so it goes in the label instead.
     */
    @RequiresApi(37)
    private fun buildMetric(context: Context, day: ClassDay, now: Instant): Notification {
        val c = Content(context, day, now)
        val e = c.focus
        val metrics = buildList {
            add(Notification.Metric(
                Notification.Metric.TimeDifference.forTimer(c.countdownTo, Notification.Metric.TimeDifference.FORMAT_CHRONOMETER),
                context.getString(if (c.inClass) R.string.live_ends_in else R.string.live_starts_in),
            ))
            add(Notification.Metric(Notification.Metric.FixedText(e.location), context.getString(R.string.detail_room)))
            c.upNext?.let { next ->
                add(Notification.Metric(Notification.Metric.FixedText(next.location), context.getString(R.string.live_next_at, next.start.time())))
            }
        }
        return Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_class)
            .setLargeIcon(Icon.createWithBitmap(badge(e)))
            .setContentTitle(if (c.inClass) e.subjectName else context.getString(R.string.next_class, e.subjectName))
            .setSubText(c.header)
            .setStyle(Notification.MetricStyle().setMetrics(metrics).setCriticalMetric(0))
            .setColor(kindArgb(e.kindCode))
            .setContentIntent(openApp(context))
            .setDeleteIntent(onDismiss(context))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setRequestPromotedOngoing(true)
            // The countdown is the first metric (and the status bar chip); a header timer would repeat it.
            .setShowWhen(false)
            .setTimeoutAfter(untilDayEnds(day, now))
            .build()
    }

    /** Android 16 and older: the day's timeline as a segmented progress bar, with the details as text. */
    private fun buildTimeline(context: Context, day: ClassDay, now: Instant): Notification {
        val c = Content(context, day, now)
        val e = c.focus
        val text = if (c.inClass) {
            listOfNotNull(
                context.getString(R.string.notif_in_class, e.kindName(context), e.end.time(), e.teacherNames),
                c.upNext?.let { nextLine(context, it) },
            ).joinToString("\n")
        } else {
            context.getString(R.string.notif_waiting, e.kindName(context), e.start.time(), e.teacherNames)
        }
        return NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_class)
            .setLargeIcon(badge(e))
            .setContentTitle(
                if (c.inClass) context.getString(R.string.notif_title, e.subjectName, e.location)
                else context.getString(R.string.notif_next_title, e.subjectName, e.location),
            )
            .setContentText(text)
            .setSubText(c.header)
            .setColor(kindArgb(e.kindCode))
            .setContentIntent(openApp(context))
            .setDeleteIntent(onDismiss(context))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setRequestPromotedOngoing(true)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setWhen(c.countdownTo.toEpochMilli())
            .setStyle(timeline(day, now, e))
            .setTimeoutAfter(untilDayEnds(day, now))
            .build()
    }

    /**
     * The system removes the notification by itself when the last class ends. The alarms that keep it
     * up to date are inexact and can come a few minutes late, so they can't be relied on for that.
     */
    private fun untilDayEnds(day: ClassDay, now: Instant): Long =
        Duration.between(now, day.end ?: now).toMillis().coerceAtLeast(1)

    private fun nextLine(context: Context, e: ClassEvent) =
        context.getString(R.string.notif_next_line, e.start.time(), e.subjectCode, e.location)

    private fun openApp(context: Context) = PendingIntent.getActivity(
        context, 0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun onDismiss(context: Context) = PendingIntent.getBroadcast(
        context, 1,
        Intent(context, PlanAlarmReceiver::class.java).setAction(PlanAlarmReceiver.ACTION_DISMISSED),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** The day as a progress bar: a segment per class (in its colour) and per break (grey). */
    private fun timeline(day: ClassDay, now: Instant, focus: ClassEvent): NotificationCompat.ProgressStyle {
        val start = day.start ?: now
        fun minutes(a: Instant, b: Instant) = Duration.between(a, b).toMinutes().toInt().coerceAtLeast(1)
        val segments = mutableListOf<NotificationCompat.ProgressStyle.Segment>()
        var cursor = start
        for (e in day.classes) {
            if (e.start.isAfter(cursor)) {
                segments += NotificationCompat.ProgressStyle.Segment(minutes(cursor, e.start)).setColor(BreakGrey)
            }
            if (e.end.isAfter(cursor)) {
                val from = if (e.start.isAfter(cursor)) e.start else cursor
                segments += NotificationCompat.ProgressStyle.Segment(minutes(from, e.end)).setColor(kindArgb(e.kindCode))
                cursor = e.end
            }
        }
        val total = segments.sumOf { it.length }
        val elapsed = Duration.between(start, now).toMinutes().toInt().coerceIn(0, total)
        return NotificationCompat.ProgressStyle()
            .setProgressSegments(segments)
            .setStyledByProgress(true)
            .setProgress(elapsed)
            .setProgressTrackerIcon(IconCompat.createWithBitmap(trackerDot(kindArgb(focus.kindCode))))
            .setProgressPoints(listOf(NotificationCompat.ProgressStyle.Point(minutes(start, focus.start).coerceAtMost(total)).setColor(kindArgb(focus.kindCode))))
    }

    private const val BreakGrey = 0xFF9E9E9E.toInt()

    /** The subject code on a rounded square in the class kind's colour, like the tinted code in the Dynamic Island. */
    private fun badge(e: ClassEvent): Bitmap {
        val size = 192
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = kindArgb(e.kindCode) }
        canvas.drawRoundRect(RectF(0f, 0f, size.toFloat(), size.toFloat()), size * 0.28f, size * 0.28f, fill)
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
            textSize = size * 0.42f
        }
        val code = e.subjectCode.ifBlank { "•" }.take(5)
        // Shrink long codes to fit the square.
        val maxWidth = size * 0.82f
        val width = text.measureText(code)
        if (width > maxWidth) text.textSize *= maxWidth / width
        val y = size / 2f - (text.descent() + text.ascent()) / 2f
        canvas.drawText(code, size / 2f, y, text)
        return bitmap
    }

    /** The marker that moves along the timeline: a dot in the class kind's colour with a white ring. */
    private fun trackerDot(argb: Int): Bitmap {
        val size = 48
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.WHITE
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.color = argb
        canvas.drawCircle(size / 2f, size / 2f, size / 2f - 7f, paint)
        return bitmap
    }

    /** Creating it again only updates its name and description, so they follow the language. */
    private fun createChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, context.getString(R.string.channel_name), NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = context.getString(R.string.channel_description)
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            },
        )
    }
}
