package it.mwojtowicz.planubb.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import it.mwojtowicz.planubb.R
import it.mwojtowicz.planubb.data.ClassEvent
import it.mwojtowicz.planubb.data.ScheduleSnapshot
import it.mwojtowicz.planubb.data.StudyTerm
import java.time.Duration

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpcomingScreen(model: ScheduleViewModel, onOpen: (ClassEvent) -> Unit, onChangeGroup: () -> Unit) {
    val snapshot by model.snapshot.collectAsStateWithLifecycle()
    val isLoading by model.isLoading.collectAsStateWithLifecycle()
    val error by model.error.collectAsStateWithLifecycle()
    val now = rememberNow()
    val context = LocalContext.current
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(stringResource(R.string.tab_upcoming)) },
                actions = { LiveToggleButton() },
                scrollBehavior = scroll,
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isLoading && snapshot != null,
            onRefresh = model::refresh,
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            val s = snapshot
            when {
                s != null -> {
                    val current = s.current(now)
                    val upcoming = s.upcoming(now, limit = 30)
                    LazyColumn(Modifier.fillMaxSize()) {
                        error?.let { item { ErrorBanner(it.userMessage(context)) } }
                        if (current != null) item { NowCard(current, now) { onOpen(current) } }
                        upcoming.firstOrNull()?.let { next -> item { NextSummary(next, now) } }
                        groupedByDay(upcoming).forEach { (day, events) ->
                            item(key = "day-$day") { SectionHeader(day.daySectionTitle(context)) }
                            events.forEach { e -> item(key = e.id) { ClassRow(e, now, onClick = { onOpen(e) }) } }
                        }
                        if (upcoming.isEmpty() && current == null) {
                            item { NoClasses(s, now, onChangeGroup) }
                        }
                    }
                }
                isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        CircularProgressIndicator()
                        Text(stringResource(R.string.downloading_plan))
                    }
                }
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    error?.let { item { ErrorBanner(it.userMessage(context)) } }
                    item { Empty(Icons.Default.EventBusy, stringResource(R.string.no_schedule_title), stringResource(R.string.no_schedule_message)) }
                }
            }
        }
    }
}

/**
 * The plan has no classes left. Usually that's a semester outside its term: even semesters have no classes
 * in autumn, odd ones none in spring, and a finished semester means the student moved on.
 */
@Composable
private fun NoClasses(snapshot: ScheduleSnapshot, now: java.time.Instant, onChangeGroup: () -> Unit) {
    val term = snapshot.planName?.let(StudyTerm::usualFor)
    val title = if (snapshot.events.isEmpty()) R.string.no_classes_title else R.string.no_upcoming_title
    val message = when {
        snapshot.events.isNotEmpty() -> if (term == null) R.string.no_upcoming_message else R.string.no_more_classes_next_semester
        term == StudyTerm.SUMMER && StudyTerm.current(now) == StudyTerm.WINTER -> R.string.no_classes_summer_term
        term == StudyTerm.WINTER && StudyTerm.current(now) == StudyTerm.SUMMER -> R.string.no_classes_winter_term
        else -> R.string.no_classes_unpublished
    }
    Empty(
        if (snapshot.events.isEmpty()) Icons.Default.DateRange else Icons.Default.CheckCircle,
        stringResource(title),
        stringResource(message),
        action = if (term == null) null else ({
            OutlinedButton(onClick = onChangeGroup) { Text(stringResource(R.string.choose_another_group)) }
        }),
    )
}

/** One-line summary: when the next class starts. */
@Composable
private fun NextSummary(event: ClassEvent, now: java.time.Instant) {
    val context = LocalContext.current
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.AutoMirrored.Filled.ArrowForward, null, tint = kindColor(event.kindCode), modifier = Modifier.size(28.dp))
        Column {
            Text(stringResource(R.string.next_class, event.subjectName), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(
                "${Duration.between(now, event.start).relative(context)} · ${event.start.timeOrDayTime()} · ${event.location}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun Empty(icon: ImageVector, title: String, message: String, action: (@Composable () -> Unit)? = null) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 64.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        action?.invoke()
    }
}
