package it.mwojtowicz.planubb.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import it.mwojtowicz.planubb.data.PlanSource
import it.mwojtowicz.planubb.data.ScheduleSnapshot
import it.mwojtowicz.planubb.data.ScheduleStore
import it.mwojtowicz.planubb.live.PlanSync
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

class ScheduleViewModel(app: Application) : AndroidViewModel(app) {
    private val store = ScheduleStore.get(app)

    val snapshot: StateFlow<ScheduleSnapshot?> = store.snapshot

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    /** The last download error; the screens turn it into a message with `userMessage`. */
    private val _error = MutableStateFlow<Throwable?>(null)
    val error: StateFlow<Throwable?> = _error.asStateFlow()

    private val _source = MutableStateFlow(store.source)
    val source: StateFlow<PlanSource> = _source.asStateFlow()

    /** False on first launch, until a group is picked. */
    private val _hasChosenSource = MutableStateFlow(store.hasChosenSource)
    val hasChosenSource: StateFlow<Boolean> = _hasChosenSource.asStateFlow()

    /** Refreshes when there's no data yet, it's for another plan, or it's older than [maxAge]. */
    fun refreshIfNeeded(maxAge: Duration = Duration.ofHours(1)) {
        if (!store.hasChosenSource) return
        val s = snapshot.value
        if (s == null || s.source != source.value || Duration.between(s.fetchedAt, Instant.now()) > maxAge) refresh()
    }

    fun refresh() {
        if (_isLoading.value) return
        _isLoading.value = true
        viewModelScope.launch {
            try {
                store.refresh()
                _error.value = null
                PlanSync.scheduleChanged(getApplication())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _error.value = e
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun changeSource(newSource: PlanSource) {
        val isFirstChoice = !store.hasChosenSource
        store.source = newSource
        _hasChosenSource.value = true
        if (newSource == _source.value && !isFirstChoice) return
        store.clear()
        _source.value = newSource
        _error.value = null
        PlanSync.scheduleChanged(getApplication())
        refresh()
    }
}
