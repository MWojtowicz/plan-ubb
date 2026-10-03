package it.mwojtowicz.planubb.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.annotation.StringRes
import androidx.compose.ui.res.stringResource
import it.mwojtowicz.planubb.R
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import android.content.pm.ApplicationInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import it.mwojtowicz.planubb.data.PlanSource
import it.mwojtowicz.planubb.data.ScheduleStore
import it.mwojtowicz.planubb.live.PlanSync

class MainActivity : ComponentActivity() {
    private val model: ScheduleViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        if (savedInstanceState == null) applyTestExtras(intent)
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            PlanUbbTheme { PlanUbbApp(model) }
        }
    }

    /**
     * Debug builds only, for UI tests (`adb shell am start … --ei plan 142113`):
     * `plan` sets the plan when none is chosen yet, skipping the first-launch picker;
     * `resetPlan` forgets the chosen plan, bringing the picker back.
     */
    private fun applyTestExtras(intent: Intent?) {
        if (intent == null || applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        val store = ScheduleStore.get(this)
        if (intent.getBooleanExtra("resetPlan", false)) {
            store.forgetSource()
        } else if (intent.hasExtra("plan") && !store.hasChosenSource) {
            store.source = PlanSource(0, intent.getIntExtra("plan", PlanSource.Default.id))
        }
    }
}

private enum class Tab(val route: String, @StringRes val label: Int, val icon: ImageVector) {
    Upcoming("upcoming", R.string.tab_upcoming, Icons.Default.Schedule),
    Week("week", R.string.tab_week, Icons.Default.CalendarMonth),
    Settings("settings", R.string.tab_settings, Icons.Default.Settings),
}

@Composable
fun PlanUbbApp(model: ScheduleViewModel) {
    val context = LocalContext.current
    val hasChosenSource by model.hasChosenSource.collectAsStateWithLifecycle()
    val source by model.source.collectAsStateWithLifecycle()

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        model.refreshIfNeeded()
        PlanSync.scheduleChanged(context)
    }

    if (!hasChosenSource) {
        GroupPicker(current = null, onPick = model::changeSource, onCancel = null)
        return
    }
    AskForNotificationsOnce()

    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route
    val showsTabs = Tab.entries.any { it.route == route }

    // Each screen has its own top bar, so this scaffold only makes room for the tab bar.
    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            if (showsTabs) {
                NavigationBar {
                    Tab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = route == tab.route,
                            onClick = {
                                nav.navigate(tab.route) {
                                    popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(tab.icon, null) },
                            label = { Text(stringResource(tab.label)) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        val openClass: (it.mwojtowicz.planubb.data.ClassEvent) -> Unit = { nav.navigate("class/${android.net.Uri.encode(it.id)}") }
        NavHost(nav, startDestination = Tab.Upcoming.route, modifier = Modifier.padding(padding).consumeWindowInsets(padding)) {
            composable(Tab.Upcoming.route) { UpcomingScreen(model, openClass) }
            composable(Tab.Week.route) { WeekScreen(model, openClass) }
            composable(Tab.Settings.route) { SettingsScreen(model, onChangeGroup = { nav.navigate("picker") }) }
            composable("class/{id}") { backStack ->
                val id = backStack.arguments?.getString("id")
                val snapshot by model.snapshot.collectAsStateWithLifecycle()
                val event = snapshot?.events?.firstOrNull { it.id == id }
                if (event != null) ClassDetailScreen(event, onBack = { nav.popBackStack() }) else nav.popBackStack()
            }
            composable("picker") {
                GroupPicker(
                    current = source,
                    onPick = { picked ->
                        nav.popBackStack()
                        model.changeSource(picked)
                    },
                    onCancel = { nav.popBackStack() },
                )
            }
        }
    }
}

/** Right after the first group is picked, ask once for the permission the live notification needs. */
@Composable
private fun AskForNotificationsOnce() {
    if (Build.VERSION.SDK_INT < 33) return
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        PlanSync.scheduleChanged(context)
    }
    LaunchedEffect(Unit) {
        val prefs = context.getSharedPreferences("live", Context.MODE_PRIVATE)
        if (prefs.getBoolean("askedForNotifications", false) || !ScheduleStore.get(context).liveUpdatesEnabled) return@LaunchedEffect
        prefs.edit { putBoolean("askedForNotifications", true) }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
