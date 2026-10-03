package it.mwojtowicz.planubb.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Podcasts
import androidx.compose.material3.FilledIconToggleButton
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import it.mwojtowicz.planubb.R
import it.mwojtowicz.planubb.data.ScheduleStore
import it.mwojtowicz.planubb.live.LiveClassNotification
import it.mwojtowicz.planubb.live.PlanSync

/** The live notification's on/off state, shared by the button on Upcoming and the switch in Settings. */
class LiveToggle(val isOn: Boolean, val set: (Boolean) -> Unit)

/** Turning it on also asks for the notification permission if it's missing (Android 13+). */
@Composable
fun rememberLiveToggle(): LiveToggle {
    val context = LocalContext.current
    val store = remember { ScheduleStore.get(context) }
    val isOn by store.liveUpdates.collectAsStateWithLifecycle()
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        PlanSync.scheduleChanged(context)
    }
    return LiveToggle(isOn) { on ->
        LiveClassNotification.setEnabled(context, on)
        if (on && Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}

/** The main-screen button: filled while the live notification is on. */
@Composable
fun LiveToggleButton() {
    val live = rememberLiveToggle()
    FilledIconToggleButton(checked = live.isOn, onCheckedChange = live.set) {
        Icon(Icons.Default.Podcasts, stringResource(if (live.isOn) R.string.live_turn_off else R.string.live_turn_on))
    }
}
