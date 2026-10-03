package it.mwojtowicz.planubb.ui

import android.content.Context
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import it.mwojtowicz.planubb.R
import android.content.res.Configuration
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import it.mwojtowicz.planubb.data.ClassEvent
import it.mwojtowicz.planubb.data.localDate
import it.mwojtowicz.planubb.data.mondayOf
import it.mwojtowicz.planubb.data.startInstant
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeekScreen(model: ScheduleViewModel, onOpen: (ClassEvent) -> Unit) {
    val snapshot by model.snapshot.collectAsStateWithLifecycle()
    val isLoading by model.isLoading.collectAsStateWithLifecycle()
    val error by model.error.collectAsStateWithLifecycle()
    val events = snapshot?.events.orEmpty()
    val thisWeek = mondayOf(LocalDate.now())
    val context = LocalContext.current

    // Every week from the first to the last class (always including this week),
    // so swiping walks through the semester week by week.
    val weeks = remember(events) {
        val first = minOf(events.firstOrNull()?.let { mondayOf(it.start.localDate()) } ?: thisWeek, thisWeek)
        val last = maxOf(events.lastOrNull()?.let { mondayOf(it.start.localDate()) } ?: thisWeek, thisWeek)
        generateSequence(first) { it.plusWeeks(1) }.takeWhile { !it.isAfter(last) }.toList()
    }
    // Mondays of all weeks that have at least one class.
    val weeksWithClasses = remember(events) { events.map { mondayOf(it.start.localDate()) }.distinct().sorted() }

    var savedWeek by rememberSaveable { mutableStateOf(thisWeek.toString()) }
    val pager = rememberPagerState(initialPage = weeks.indexOf(LocalDate.parse(savedWeek)).coerceAtLeast(0)) { weeks.size }
    val scope = rememberCoroutineScope()
    val monday = weeks.getOrElse(pager.currentPage) { thisWeek }
    // The weeks change when the plan downloads; stay on the week the user was looking at.
    LaunchedEffect(weeks) {
        val i = weeks.indexOf(LocalDate.parse(savedWeek))
        if (i >= 0 && i != pager.currentPage) pager.scrollToPage(i)
        snapshotFlow { pager.settledPage }.collect { page -> weeks.getOrNull(page)?.let { savedWeek = it.toString() } }
    }
    fun go(week: LocalDate) {
        val i = weeks.indexOf(week)
        if (i >= 0) scope.launch { pager.animateScrollToPage(i) }
    }

    var showsMenu by remember { mutableStateOf(false) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.tab_week)) },
                navigationIcon = {
                    TextButton(onClick = { go(thisWeek) }, enabled = monday != thisWeek) { Text(stringResource(R.string.today)) }
                },
                actions = {
                    Box {
                        IconButton(onClick = { showsMenu = true }, enabled = weeksWithClasses.isNotEmpty()) {
                            Icon(Icons.AutoMirrored.Filled.List, stringResource(R.string.weeks))
                        }
                        DropdownMenu(expanded = showsMenu, onDismissRequest = { showsMenu = false }) {
                            weeksWithClasses.forEach { week ->
                                DropdownMenuItem(
                                    text = { Text(weekTitle(week)) },
                                    leadingIcon = { if (week == monday) Icon(Icons.Default.Check, null) },
                                    onClick = { showsMenu = false; go(week) },
                                )
                            }
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { go(weeks[pager.currentPage - 1]) }, enabled = pager.currentPage > 0) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, stringResource(R.string.previous_week))
                }
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(weekTitle(monday), style = MaterialTheme.typography.titleMedium)
                    Text(weekSubtitle(context, events, monday), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = { go(weeks[pager.currentPage + 1]) }, enabled = pager.currentPage < weeks.lastIndex) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, stringResource(R.string.next_week))
                }
            }
            HorizontalDivider()
            error?.let { ErrorBanner(it.userMessage(context)) }
            HorizontalPager(pager, Modifier.fillMaxSize(), key = { weeks[it].toString() }) { page ->
                val week = weeks[page]
                val days = groupedByDay(events.filter { it.start.localDate() >= week && it.start.localDate() < week.plusWeeks(1) })
                when {
                    days.isNotEmpty() -> PullToRefreshBox(isRefreshing = isLoading, onRefresh = model::refresh) {
                        WeekPage(days, onOpen)
                    }
                    isLoading && snapshot == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                    else -> {
                        val next = weeksWithClasses.firstOrNull { it > week }
                        Empty(Icons.Default.CalendarMonth, stringResource(R.string.no_classes_this_week), "") {
                            if (next != null) FilledTonalButton(onClick = { go(next) }) { Text(stringResource(R.string.go_to_next_week_with_classes)) }
                        }
                    }
                }
            }
        }
    }
}

/** A list in portrait, side-by-side day columns in landscape (like the timetable on the website). */
@Composable
private fun WeekPage(days: List<Pair<LocalDate, List<ClassEvent>>>, onOpen: (ClassEvent) -> Unit) {
    val now = rememberNow(15_000)
    val context = LocalContext.current
    if (LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE) {
        Row(
            Modifier.fillMaxSize().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            days.forEach { (day, events) ->
                LazyColumn(Modifier.width(280.dp).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    item {
                        Text(
                            day.daySectionTitle(context),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                    events.forEach { e ->
                        item(key = e.id) {
                            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                                ClassRow(e, now, onClick = { onOpen(e) })
                            }
                        }
                    }
                }
            }
        }
    } else {
        LazyColumn(Modifier.fillMaxSize()) {
            days.forEach { (day, events) ->
                item(key = "day-$day") { SectionHeader(day.daySectionTitle(context)) }
                events.forEach { e -> item(key = e.id) { ClassRow(e, now, onClick = { onOpen(e) }) } }
            }
        }
    }
}

private fun weekTitle(monday: LocalDate) = "${monday.formatSkeleton("dMMM")} – ${monday.plusDays(6).formatSkeleton("dMMMyyyy")}"

private fun weekSubtitle(context: Context, events: List<ClassEvent>, monday: LocalDate): String {
    val from: Instant = monday.startInstant()
    val to: Instant = monday.plusWeeks(1).startInstant()
    val week = events.filter { !it.start.isBefore(from) && it.start.isBefore(to) }
    if (week.isEmpty()) return context.getString(R.string.no_classes)
    val hours = week.sumOf { it.duration.toMinutes() } / 60.0
    val h = if (hours % 1.0 == 0.0) "%.0f".format(hours) else "%.1f".format(hours)
    val classes = context.resources.getQuantityString(R.plurals.class_count, week.size, week.size)
    return context.getString(R.string.week_summary, classes, h)
}
