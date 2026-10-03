package it.mwojtowicz.planubb.live

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
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
 * The Android counterpart of the iOS Live Activity: an ongoing notification for the day's classes.
 *
 * On Android 16+ it asks to be promoted to a "Live Update", so it sits at the top of the lock screen
 * and shows a countdown chip in the status bar. Its progress bar is the day's timeline: one coloured
 * segment per class, grey for the breaks, filled up to now. The countdown is a system chronometer,
 * so it ticks on its own; [PlanSync] refreshes the rest at every class boundary and every few minutes.
 */
object LiveClassNotification {
    private const val CHANNEL = "live"
    private const val ID = 1
    /** Show from this long before the first class of the day. */
    val Lead: Duration = Duration.ofHours(1)
    /** How often the timeline is redrawn while the notification is up. */
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

    /** Whether it should be up at [now]: during a class, in a break, or within [Lead] of the first class. */
    fun shouldShow(day: ClassDay, now: Instant): Boolean = when (val phase = day.phase(now)) {
        is ClassDay.Phase.InClass -> true
        is ClassDay.Phase.Waiting -> phase.since != null || Duration.between(now, phase.next.start) <= Lead
        ClassDay.Phase.Done -> false
    }

    /** Posts, updates or removes the notification. Returns true if it's showing. */
    fun update(context: Context, now: Instant = Instant.now()): Boolean {
        val store = ScheduleStore.get(context)
        val snapshot = store.snapshot.value
        val day = snapshot?.let { ClassDay.of(it, now) }
        val prefs = context.getSharedPreferences("live", Context.MODE_PRIVATE)
        val dismissedToday = prefs.getString("dismissedOn", null) == now.localDate().toString()
        if (!store.liveUpdatesEnabled || !store.hasChosenSource || day == null || dismissedToday || !shouldShow(day, now) || !canPost(context)) {
            cancel(context)
            return false
        }
        createChannel(context)
        try {
            NotificationManagerCompat.from(context).notify(ID, build(context, day, now))
        } catch (e: SecurityException) {
            return false
        }
        return true
    }

    fun cancel(context: Context) = NotificationManagerCompat.from(context).cancel(ID)

    /** The user swiped it away: leave it gone until tomorrow. */
    fun dismissedByUser(context: Context) {
        context.getSharedPreferences("live", Context.MODE_PRIVATE).edit {
            putString("dismissedOn", Instant.now().localDate().toString())
        }
    }

    private fun build(context: Context, day: ClassDay, now: Instant): android.app.Notification {
        val phase = day.phase(now)
        val focus = when (phase) {
            is ClassDay.Phase.InClass -> phase.event
            is ClassDay.Phase.Waiting -> phase.next
            ClassDay.Phase.Done -> error("not shown when done")
        }
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val delete = PendingIntent.getBroadcast(
            context, 1,
            Intent(context, PlanAlarmReceiver::class.java).setAction(PlanAlarmReceiver.ACTION_DISMISSED),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_class)
            .setContentIntent(open)
            .setDeleteIntent(delete)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setRequestPromotedOngoing(true)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)

        when (phase) {
            is ClassDay.Phase.InClass -> {
                val e = phase.event
                builder
                    .setContentTitle(context.getString(R.string.notif_title, e.subjectName, e.location))
                    .setContentText(
                        listOfNotNull(
                            context.getString(R.string.notif_in_class, e.kindName(context), e.end.time(), e.teacherNames),
                            phase.next?.let { nextLine(context, it) },
                        ).joinToString("\n"),
                    )
                    .setSubText(context.getString(R.string.now))
                    .setWhen(e.end.toEpochMilli())
            }
            is ClassDay.Phase.Waiting -> {
                val e = phase.next
                builder
                    .setContentTitle(context.getString(R.string.notif_next_title, e.subjectName, e.location))
                    .setContentText(context.getString(R.string.notif_waiting, e.kindName(context), e.start.time(), e.teacherNames))
                    .setSubText(context.getString(if (phase.since == null) R.string.notif_first_class else R.string.notif_break))
                    .setWhen(e.start.toEpochMilli())
            }
            ClassDay.Phase.Done -> Unit
        }
        builder.setStyle(timeline(day, now, focus))
        return builder.build()
    }

    private fun nextLine(context: Context, e: ClassEvent) =
        context.getString(R.string.notif_next_line, e.start.time(), e.subjectCode, e.location)

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
        val elapsed = Duration.between(start, now).toMinutes().toInt().coerceIn(0, segments.sumOf { it.length })
        return NotificationCompat.ProgressStyle()
            .setProgressSegments(segments)
            .setStyledByProgress(true)
            .setProgress(elapsed)
            .setProgressPoints(listOf(NotificationCompat.ProgressStyle.Point(minutes(start, focus.start).coerceAtMost(segments.sumOf { it.length })).setColor(kindArgb(focus.kindCode))))
    }

    private const val BreakGrey = 0xFF9E9E9E.toInt()

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
