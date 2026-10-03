package it.mwojtowicz.planubb.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.format.DateUtils
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import it.mwojtowicz.planubb.R
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import it.mwojtowicz.planubb.data.PlanSource
import it.mwojtowicz.planubb.data.ScheduleStore
import it.mwojtowicz.planubb.live.LiveClassNotification
import it.mwojtowicz.planubb.live.PlanSync

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(model: ScheduleViewModel, onChangeGroup: () -> Unit) {
    val context = LocalContext.current
    val store = remember { ScheduleStore.get(context) }
    val snapshot by model.snapshot.collectAsStateWithLifecycle()
    val isLoading by model.isLoading.collectAsStateWithLifecycle()
    val error by model.error.collectAsStateWithLifecycle()
    val source by model.source.collectAsStateWithLifecycle()
    val now = rememberNow(30_000)
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    var planInput by remember(source) { mutableStateOf(source.webUrl) }
    var inputInvalid by remember { mutableStateOf(false) }

    var liveOn by remember { mutableStateOf(store.liveUpdatesEnabled) }
    var canNotify by remember { mutableStateOf(LiveClassNotification.canPost(context)) }
    var canPromote by remember { mutableStateOf(LiveClassNotification.canPromote(context)) }
    // Re-check when coming back from the system settings.
    LifecycleResumeEffect(Unit) {
        canNotify = LiveClassNotification.canPost(context)
        canPromote = LiveClassNotification.canPromote(context)
        onPauseOrDispose { }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        canNotify = granted
        PlanSync.scheduleChanged(context)
    }
    fun setLive(on: Boolean) {
        liveOn = on
        store.liveUpdatesEnabled = on
        if (on && Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        PlanSync.scheduleChanged(context)
    }

    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = { LargeTopAppBar(title = { Text(stringResource(R.string.tab_settings)) }, scrollBehavior = scroll) },
    ) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize()) {
            item { ListItem(headlineContent = { Text(stringResource(R.string.settings_plan)) }, trailingContent = { Text(snapshot?.planName ?: "—") }) }
            item { ListItem(headlineContent = { Text(stringResource(R.string.settings_classes)) }, trailingContent = { Text("${snapshot?.events?.size ?: 0}") }) }
            item {
                val updated = snapshot?.fetchedAt?.let {
                    if (now.toEpochMilli() - it.toEpochMilli() < DateUtils.MINUTE_IN_MILLIS) stringResource(R.string.just_now)
                    else DateUtils.getRelativeTimeSpanString(it.toEpochMilli(), now.toEpochMilli(), DateUtils.MINUTE_IN_MILLIS).toString()
                } ?: stringResource(R.string.never)
                ListItem(headlineContent = { Text(stringResource(R.string.settings_updated)) }, trailingContent = { Text(updated) })
            }
            item {
                Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    FilledTonalButton(onClick = onChangeGroup) { Text(stringResource(R.string.change_group)) }
                    TextButton(onClick = model::refresh, enabled = !isLoading) { Text(stringResource(R.string.refresh_now)) }
                    if (isLoading) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                }
            }
            error?.let { item { ErrorBanner(it.userMessage(context)) } }

            item { HorizontalDivider(Modifier.padding(top = 12.dp)) }
            item { SectionHeader(stringResource(R.string.live_notification)) }
            item {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.show_during_classes)) },
                    supportingContent = {
                        Text(stringResource(R.string.live_notification_description))
                    },
                    trailingContent = { Switch(checked = liveOn, onCheckedChange = ::setLive) },
                    modifier = Modifier.clickable { setLive(!liveOn) },
                )
            }
            if (liveOn && !canNotify) {
                item {
                    Hint(stringResource(R.string.notifications_off), stringResource(R.string.open_settings)) {
                        context.startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
                        )
                    }
                }
            } else if (liveOn && !canPromote) {
                item {
                    Hint(stringResource(R.string.live_updates_off), stringResource(R.string.turn_on)) {
                        LiveClassNotification.openPromotionSettings(context)
                    }
                }
            }

            item { HorizontalDivider(Modifier.padding(top = 12.dp)) }
            item { SectionHeader(stringResource(R.string.plan_address)) }
            item {
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = planInput,
                        onValueChange = { planInput = it; inputInvalid = false },
                        label = { Text(stringResource(R.string.plan_url_or_id)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                        isError = inputInvalid,
                        supportingText = if (inputInvalid) ({ Text(stringResource(R.string.invalid_plan)) }) else null,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilledTonalButton(
                            onClick = {
                                val parsed = PlanSource.parse(planInput)
                                if (parsed == null) inputInvalid = true
                                else model.changeSource(parsed)
                            },
                            enabled = planInput.isNotBlank(),
                        ) { Text(stringResource(R.string.use_this_plan)) }
                        TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(source.webUrl))) }) {
                            Icon(Icons.AutoMirrored.Filled.OpenInNew, null, Modifier.size(18.dp))
                            Text("  " + stringResource(R.string.open_on_site))
                        }
                    }
                    Text(
                        stringResource(R.string.plan_address_footer, source.type, source.id),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(bottom = 24.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun Hint(message: String, action: String, onAction: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error, modifier = Modifier.weight(1f))
        TextButton(onClick = onAction) { Text(action) }
    }
}
