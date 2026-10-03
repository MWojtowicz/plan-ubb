package it.mwojtowicz.planubb.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val UbbBlue = Color(0xFF0A5BB5)

@Composable
fun PlanUbbTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    val colors = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> darkColorScheme(primary = Color(0xFF9CC3FF))
        else -> lightColorScheme(primary = UbbBlue)
    }
    MaterialTheme(colorScheme = colors, content = content)
}

/** Colours follow the ones used on plany.ubb.edu.pl. */
fun kindColor(kindCode: String): Color = Color(kindArgb(kindCode))

fun kindArgb(kindCode: String): Int = when (kindCode.lowercase()) {
    "wyk" -> 0xFF4FB300.toInt()
    "lab" -> 0xFF7373F2.toInt()
    "ćw", "cw" -> 0xFF33A8E6.toInt()
    "lek" -> 0xFFF2A833.toInt()
    "proj", "pro" -> 0xFFD9598C.toInt()
    else -> 0xFF8E8E93.toInt()
}
