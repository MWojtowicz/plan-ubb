package it.mwojtowicz.planubb.live

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.glance.appwidget.updateAll
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import it.mwojtowicz.planubb.data.ScheduleStore
import it.mwojtowicz.planubb.widget.CurrentClassWidget
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit

/**
 * Keeps the widget and the live notification in step with the schedule and the clock.
 *
 * Unlike iOS, Android lets the app wake itself up, so an alarm is set for the next moment anything
 * visible changes: a class starting or ending, the live notification's lead time, or (while it's up)
 * the next timeline redraw. Inexact alarms are used, so they can arrive a few minutes late in Doze;
 * the countdowns are system chronometers and stay exact regardless.
 */
object PlanSync {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Call after the schedule, the chosen plan or a setting changed. */
    fun scheduleChanged(context: Context) {
        val app = context.applicationContext
        scope.launch { sync(app) }
    }

    suspend fun sync(context: Context, now: Instant = Instant.now()) {
        val showing = LiveClassNotification.update(context, now)
        runCatching { CurrentClassWidget().updateAll(context) }
        scheduleAlarm(context, nextWake(context, now, showing))
        RefreshWorker.schedule(context)
    }

    private fun nextWake(context: Context, now: Instant, showing: Boolean): Instant? {
        val events = ScheduleStore.get(context).snapshot.value?.events ?: return null
        val candidates = mutableListOf<Instant>()
        events.asSequence().flatMap { sequenceOf(it.start, it.end) }.filter { it.isAfter(now) }.minOrNull()?.let(candidates::add)
        events.firstOrNull { it.start.isAfter(now) }?.start?.minus(LiveClassNotification.Lead)?.takeIf { it.isAfter(now) }?.let(candidates::add)
        if (showing) candidates += now.plus(LiveClassNotification.RefreshEvery)
        return candidates.minOrNull()
    }

    private fun scheduleAlarm(context: Context, at: Instant?) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val intent = PendingIntent.getBroadcast(
            context, 0,
            Intent(context, PlanAlarmReceiver::class.java).setAction(PlanAlarmReceiver.ACTION_TICK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        alarms.cancel(intent)
        if (at != null) alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), intent)
    }
}

/** Alarm ticks, the notification being swiped away, and system events that move the clock or wipe alarms. */
class PlanAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_DISMISSED) LiveClassNotification.dismissedByUser(context)
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                PlanSync.sync(context.applicationContext)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ACTION_TICK = "it.mwojtowicz.planubb.TICK"
        const val ACTION_DISMISSED = "it.mwojtowicz.planubb.DISMISSED"
    }
}

/** Re-downloads the plan every few hours, so the widget and notification follow changes without opening the app. */
class RefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val store = ScheduleStore.get(applicationContext)
        if (!store.hasChosenSource) return Result.success()
        val snapshot = store.snapshot.value
        if (snapshot != null && Duration.between(snapshot.fetchedAt, Instant.now()) < Duration.ofHours(5)) return Result.success()
        return try {
            store.refresh()
            PlanSync.sync(applicationContext)
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    companion object {
        fun schedule(context: Context) {
            if (!ScheduleStore.get(context).hasChosenSource) return
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "refresh",
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<RefreshWorker>(6, TimeUnit.HOURS)
                    .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                    .build(),
            )
        }
    }
}
