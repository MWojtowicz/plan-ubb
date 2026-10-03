package it.mwojtowicz.planubb.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Podcasts
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import it.mwojtowicz.planubb.R
import it.mwojtowicz.planubb.data.ClassEvent
import kotlinx.coroutines.delay
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

/** The current time, updated every [periodMillis]. */
@Composable
fun rememberNow(periodMillis: Long = 1_000): Instant {
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(periodMillis) {
        while (true) {
            now = Instant.now()
            delay(periodMillis - System.currentTimeMillis() % periodMillis)
        }
    }
    return now
}

/** A list row: time column, then subject, location and teacher. */
@Composable
fun ClassRow(event: ClassEvent, now: Instant, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val tint = kindColor(event.kindCode)
    Row(
        modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.widthIn(min = 52.dp), horizontalAlignment = Alignment.End) {
            Text(event.start.time(), style = MaterialTheme.typography.titleSmall)
            Text(event.end.time(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Box(Modifier.width(4.dp).fillMaxHeight().background(tint, RoundedCornerShape(2.dp)))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(event.subjectName, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                KindBadge(event)
            }
            IconLine(Icons.Default.Place, event.location)
            IconLine(Icons.Default.Person, event.teacherNames)
            if (event.isRunning(now)) {
                Text(
                    stringResource(R.string.ends_in, Duration.between(now, event.end).countdown()),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = tint,
                )
            }
        }
    }
}

@Composable
fun KindBadge(event: ClassEvent) {
    val tint = kindColor(event.kindCode)
    Text(
        event.kindName(LocalContext.current),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = tint,
        modifier = Modifier
            .background(tint.copy(alpha = 0.18f), RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

@Composable
fun IconLine(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, contentDescription = null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Large card for the class that is running right now. */
@Composable
fun NowCard(event: ClassEvent, now: Instant, onClick: () -> Unit) {
    val tint = kindColor(event.kindCode)
    val total = event.duration.toMillis().coerceAtLeast(1)
    val elapsed = Duration.between(event.start, now).toMillis()
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Podcasts, null, Modifier.size(16.dp), tint = tint)
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.now), color = tint, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                KindBadge(event)
            }
            Text(event.subjectName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(
                Duration.between(now, event.end).countdown(),
                fontSize = 44.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.SansSerif,
            )
            LinearProgressIndicator(
                progress = { (elapsed.toFloat() / total).coerceIn(0f, 1f) },
                color = tint,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(stringResource(R.string.until_time, event.end.time()), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            IconLine(Icons.Default.Place, event.location)
            IconLine(Icons.Default.Person, event.teacherNames)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClassDetailScreen(event: ClassEvent, onBack: () -> Unit) {
    val context = LocalContext.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(event.subjectCode) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back)) }
                },
            )
        },
    ) { padding ->
        LazyColumn(contentPadding = padding) {
            item {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(event.subjectName, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        KindBadge(event)
                        Text(event.subjectCode, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            item { SectionHeader(stringResource(R.string.detail_when)) }
            item { ListItem(headlineContent = { Text(stringResource(R.string.detail_date)) }, trailingContent = { Text(event.start.atZone(ZoneId.systemDefault()).formatSkeleton("EEEEdMMMMyyyy")) }) }
            item { ListItem(headlineContent = { Text(stringResource(R.string.detail_time)) }, trailingContent = { Text(event.timeRange(context)) }) }
            item { ListItem(headlineContent = { Text(stringResource(R.string.detail_duration)) }, trailingContent = { Text(event.duration.length(context)) }) }
            item { HorizontalDivider() }
            item { SectionHeader(stringResource(if (event.rooms.size > 1) R.string.detail_rooms else R.string.detail_room)) }
            event.rooms.forEach { room -> item { ListItem(headlineContent = { Text(room) }) } }
            item { HorizontalDivider() }
            item { SectionHeader(stringResource(if (event.teachers.size > 1) R.string.detail_teachers else R.string.detail_teacher)) }
            event.teachers.forEach { t -> item { ListItem(headlineContent = { Text(t) }) } }
        }
    }
}

@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier.padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 6.dp),
    )
}

@Composable
fun ErrorBanner(message: String, modifier: Modifier = Modifier) {
    Row(
        modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Default.Warning, null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(18.dp))
        Text(message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
    }
}
