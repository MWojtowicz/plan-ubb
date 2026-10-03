package it.mwojtowicz.planubb.ui

import android.content.Context
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import it.mwojtowicz.planubb.R
import it.mwojtowicz.planubb.data.TreeLabels
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import it.mwojtowicz.planubb.data.PlanSource
import it.mwojtowicz.planubb.data.PlanTreeNode
import it.mwojtowicz.planubb.data.PlanTreeService
import kotlinx.coroutines.CancellationException

/** A level the user has opened, with its siblings so its title can be shortened like in the list. */
private data class Level(val node: PlanTreeNode, val siblings: List<PlanTreeNode>)

/**
 * Drill-down through the site's "Grupy" tree: department → study mode → course → degree →
 * semester → group → subgroup. Each level is downloaded when it's opened, like the site's left frame.
 *
 * [onCancel] is null on first launch, when a group must be picked.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupPicker(current: PlanSource?, onPick: (PlanSource) -> Unit, onCancel: (() -> Unit)?) {
    val isOnboarding = onCancel == null
    val service = remember { PlanTreeService() }
    val cache = remember { mutableStateMapOf<String, List<PlanTreeNode>>() }
    val path = remember { mutableStateListOf<Level>() }

    BackHandler(enabled = path.isNotEmpty() || onCancel != null) {
        if (path.isNotEmpty()) path.removeAt(path.lastIndex) else onCancel?.invoke()
    }

    val level = path.lastOrNull()
    val labels = treeLabels(LocalContext.current)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(level?.let { it.node.shortName(it.siblings, labels) } ?: if (isOnboarding) stringResource(R.string.app_name) else stringResource(R.string.choose_group)) },
                navigationIcon = {
                    when {
                        path.isNotEmpty() -> IconButton(onClick = { path.removeAt(path.lastIndex) }) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back))
                        }
                        onCancel != null -> IconButton(onClick = onCancel) { Icon(Icons.Default.Close, stringResource(R.string.cancel)) }
                    }
                },
            )
        },
    ) { padding ->
        AnimatedContent(
            targetState = path.toList(),
            transitionSpec = {
                val forward = targetState.size >= initialState.size
                (slideInHorizontally { if (forward) it / 3 else -it / 3 } + fadeIn()) togetherWith
                    (slideOutHorizontally { if (forward) -it / 3 else it / 3 } + fadeOut())
            },
            contentKey = { it.size to it.lastOrNull()?.node?.key },
            modifier = Modifier.padding(padding),
            label = "level",
        ) { stack ->
            val parent = stack.lastOrNull()?.node
            LevelList(
                parent = parent,
                isOnboarding = isOnboarding && stack.isEmpty(),
                current = current,
                load = {
                    val key = parent?.key ?: "root"
                    cache[key] ?: service.children(parent).also { cache[key] = it }
                },
                onOpen = { node, siblings -> path.add(Level(node, siblings)) },
                onPick = onPick,
            )
        }
    }
}

@Composable
private fun LevelList(
    parent: PlanTreeNode?,
    isOnboarding: Boolean,
    current: PlanSource?,
    load: suspend () -> List<PlanTreeNode>,
    onOpen: (PlanTreeNode, List<PlanTreeNode>) -> Unit,
    onPick: (PlanSource) -> Unit,
) {
    var nodes by remember { mutableStateOf<List<PlanTreeNode>?>(null) }
    var error by remember { mutableStateOf<Throwable?>(null) }
    val context = LocalContext.current
    val labels = treeLabels(context)
    var attempt by remember { mutableStateOf(0) }
    var query by remember { mutableStateOf("") }

    LaunchedEffect(attempt) {
        error = null
        try {
            nodes = load()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e
        }
    }

    LazyColumn(Modifier.fillMaxSize().testTag("groupLevel")) {
        if (isOnboarding) {
            item {
                Card(Modifier.fillMaxWidth().padding(16.dp)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Default.Groups, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.choose_your_group), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        Text(
                            stringResource(R.string.picker_intro),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        val all = nodes
        when {
            all != null -> {
                if (all.size > 6) {
                    item {
                        OutlinedTextField(
                            value = query,
                            onValueChange = { query = it },
                            placeholder = { Text(stringResource(R.string.search)) },
                            leadingIcon = { Icon(Icons.Default.Search, null) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }
                }
                val q = query.trim()
                val shown = if (q.isEmpty()) all else all.filter {
                    it.name.contains(q, ignoreCase = true) || it.shortName(all, labels).contains(q, ignoreCase = true)
                }
                items(shown, key = { it.key }) { node ->
                    val short = node.shortName(all, labels)
                    val plan = node.plan
                    val isLeafPlan = node.isLeaf && plan != null
                    ListItem(
                        headlineContent = { Text(short) },
                        supportingContent = if (short != node.name) ({ Text(node.name) }) else null,
                        trailingContent = {
                            when {
                                isLeafPlan && plan == current -> Icon(Icons.Default.Check, stringResource(R.string.current), tint = MaterialTheme.colorScheme.primary)
                                !node.isLeaf -> Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null)
                            }
                        },
                        modifier = Modifier.clickable { if (isLeafPlan) onPick(plan!!) else onOpen(node, all) },
                    )
                    HorizontalDivider(Modifier.padding(start = 16.dp))
                }
                if (all.isEmpty()) item { ListItem(headlineContent = { Text(stringResource(R.string.nothing_here)) }) }
                val parentPlan = parent?.plan
                if (parentPlan != null && all.isNotEmpty()) {
                    item {
                        ListItem(
                            leadingContent = { Icon(Icons.Default.ViewAgenda, null) },
                            headlineContent = { Text(stringResource(R.string.use_whole_plan, parent.name)) },
                            supportingContent = { Text(stringResource(R.string.use_whole_plan_footer)) },
                            modifier = Modifier.padding(top = 16.dp).clickable { onPick(parentPlan) },
                        )
                    }
                }
            }
            error != null -> item {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ErrorBanner(error!!.userMessage(context, fallback = R.string.error_load_list))
                    OutlinedButton(onClick = { attempt++ }) { Text(stringResource(R.string.try_again)) }
                }
            }
            else -> item {
                Box(Modifier.fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
        }
    }
}

/** "Semester 3", "Group 1", "Subgroup b" in the user's language. */
private fun treeLabels(context: Context) = TreeLabels(
    semester = { context.getString(R.string.tree_semester, it) },
    group = { context.getString(R.string.tree_group, it) },
    subgroup = { context.getString(R.string.tree_subgroup, it) },
)
