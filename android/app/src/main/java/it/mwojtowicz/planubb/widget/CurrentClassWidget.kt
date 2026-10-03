package it.mwojtowicz.planubb.widget

import android.content.Context
import android.os.SystemClock
import android.widget.RemoteViews
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import it.mwojtowicz.planubb.R
import it.mwojtowicz.planubb.data.ClassEvent
import it.mwojtowicz.planubb.data.ScheduleSnapshot
import it.mwojtowicz.planubb.data.ScheduleStore
import it.mwojtowicz.planubb.ui.MainActivity
import it.mwojtowicz.planubb.ui.kindColor
import it.mwojtowicz.planubb.ui.kindName
import it.mwojtowicz.planubb.ui.timeRange
import it.mwojtowicz.planubb.ui.time
import it.mwojtowicz.planubb.ui.timeOrDayTime
import java.time.Duration
import java.time.Instant

/**
 * "Current class": the class running now with a countdown to its end, or the next one.
 * [it.mwojtowicz.planubb.live.PlanSync] redraws it at every class start and end.
 */
class CurrentClassWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(Small, Medium))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val store = ScheduleStore.get(context)
        var snapshot = store.snapshot.value
        // Before the first group is picked there's nothing to download yet.
        if (store.hasChosenSource && (snapshot == null || Duration.between(snapshot.fetchedAt, Instant.now()) > Duration.ofHours(6))) {
            runCatching { store.refresh() }.onSuccess { snapshot = it }
        }
        val hasData = snapshot != null
        val data = snapshot
        provideContent {
            GlanceTheme {
                Content(data, hasData, Instant.now())
            }
        }
    }

    @Composable
    private fun Content(snapshot: ScheduleSnapshot?, hasData: Boolean, now: Instant) {
        val current = snapshot?.current(now)
        val next = snapshot?.upcoming(now, 1)?.firstOrNull()
        val isMedium = LocalSize.current.width >= Medium.width
        val context = LocalContext.current
        Column(
            GlanceModifier
                .fillMaxSize()
                .background(GlanceTheme.colors.widgetBackground)
                .cornerRadius(20.dp)
                .padding(14.dp)
                .clickable(actionStartActivity<MainActivity>()),
        ) {
            when {
                current != null -> {
                    Label(context.getString(R.string.widget_now), current)
                    Text(current.subjectName, style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 15.sp, color = GlanceTheme.colors.onSurface), maxLines = 2)
                    AndroidRemoteViews(countdown(context, current.end, now))
                    Details(current, isMedium)
                }
                next != null -> {
                    Label(context.getString(R.string.widget_next, next.start.timeOrDayTime()), next)
                    Text(next.subjectName, style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 15.sp, color = GlanceTheme.colors.onSurface), maxLines = 2)
                    Spacer(GlanceModifier.height(4.dp))
                    Details(next, isMedium)
                }
                else -> Text(
                    context.getString(if (hasData) R.string.no_upcoming_title else R.string.widget_open_app),
                    style = TextStyle(fontWeight = FontWeight.Bold, color = GlanceTheme.colors.onSurface),
                )
            }
        }
    }

    @Composable
    private fun Label(text: String, event: ClassEvent) {
        Text(text, style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 12.sp, color = ColorProvider(kindColor(event.kindCode), kindColor(event.kindCode))))
    }

    @Composable
    private fun Details(e: ClassEvent, isMedium: Boolean) {
        val style = TextStyle(fontSize = 12.sp, color = GlanceTheme.colors.onSurfaceVariant)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⌖ ${e.location}", style = style, maxLines = 1)
        }
        Text("👤 ${e.teacherNames}", style = style, maxLines = 1)
        if (isMedium) {
            val context = LocalContext.current
            Text("${e.kindName(context)} · ${e.timeRange(context)}", style = style, maxLines = 1)
        }
    }

    /** A system-drawn countdown, so it ticks without redrawing the widget. */
    private fun countdown(context: Context, end: Instant, now: Instant): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_countdown).apply {
            val base = SystemClock.elapsedRealtime() + Duration.between(now, end).toMillis()
            setChronometer(R.id.countdown, base, null, true)
            setChronometerCountDown(R.id.countdown, true)
        }

    companion object {
        private val Small = DpSize(110.dp, 110.dp)
        private val Medium = DpSize(250.dp, 110.dp)
    }
}

class CurrentClassWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = CurrentClassWidget()
}
