package it.mwojtowicz.planubb.data

import android.content.Context
import androidx.core.content.edit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Persists the chosen plan and the downloaded schedule. The app, the widget and the live notification
 * all read from here, so whatever one of them downloads, the others see.
 */
class ScheduleStore private constructor(context: Context) {
    private val prefs = context.getSharedPreferences("plan", Context.MODE_PRIVATE)
    private val folder = File(context.filesDir, "schedule").apply { mkdirs() }
    private val json = Json { ignoreUnknownKeys = true }
    private val refreshLock = Mutex()

    private val _snapshot = MutableStateFlow(load<ScheduleSnapshot>("snapshot.json"))
    /** The cached schedule; updates whenever a refresh finishes. */
    val snapshot: StateFlow<ScheduleSnapshot?> = _snapshot.asStateFlow()

    /** False until the user picks a group (first launch). [source] falls back to the default until then. */
    val hasChosenSource: Boolean get() = prefs.contains("source")

    var source: PlanSource
        get() = prefs.getString("source", null)?.let { runCatching { json.decodeFromString<PlanSource>(it) }.getOrNull() }
            ?: PlanSource.Default
        set(value) = prefs.edit { putString("source", json.encodeToString(PlanSource.serializer(), value)) }

    /** Show the "classes today" live notification. On by default. */
    var liveUpdatesEnabled: Boolean
        get() = prefs.getBoolean("liveUpdatesEnabled", true)
        set(value) = prefs.edit { putBoolean("liveUpdatesEnabled", value) }

    fun loadDirectory(): NameDirectory = load("names.json") ?: NameDirectory()

    /** Forgets the cached schedule and names (when switching plans). */
    fun clear() {
        File(folder, "snapshot.json").delete()
        File(folder, "names.json").delete()
        _snapshot.value = null
    }

    /** Back to first-launch state: no plan chosen, nothing cached. */
    fun forgetSource() {
        prefs.edit { remove("source") }
        clear()
    }

    /** Downloads the current source's plan and stores it. Concurrent calls share one download. */
    suspend fun refresh(service: ScheduleService = ScheduleService()): ScheduleSnapshot = refreshLock.withLock {
        val (snapshot, directory) = service.fetch(source, loadDirectory())
        write(directory, NameDirectory.serializer(), "names.json")
        write(snapshot, ScheduleSnapshot.serializer(), "snapshot.json")
        _snapshot.value = snapshot
        snapshot
    }

    private inline fun <reified T> load(name: String): T? = runCatching {
        json.decodeFromString<T>(File(folder, name).readText())
    }.getOrNull()

    private fun <T> write(value: T, serializer: kotlinx.serialization.KSerializer<T>, name: String) {
        val tmp = File(folder, "$name.tmp")
        tmp.writeText(json.encodeToString(serializer, value))
        tmp.renameTo(File(folder, name))
    }

    companion object {
        @Volatile private var instance: ScheduleStore? = null

        fun get(context: Context): ScheduleStore =
            instance ?: synchronized(this) {
                instance ?: ScheduleStore(context.applicationContext).also { instance = it }
            }
    }
}
