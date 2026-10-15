package dev.torrentlens.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.torrentlens.app.di.EngineStatus
import dev.torrentlens.app.ui.Format
import dev.torrentlens.app.ui.components.EmptyState
import dev.torrentlens.app.ui.components.InlineNotice
import dev.torrentlens.core.data.settings.AppSettings
import dev.torrentlens.core.data.repo.TorrentTaskRecord
import dev.torrentlens.core.domain.model.LibraryItem

/** Dashboard: what is happening now, plus recent activity. */
@Composable
fun DashboardScreen(
    tasks: List<TorrentTaskRecord>,
    library: List<LibraryItem>,
    settings: AppSettings,
    engineStatus: EngineStatus,
    modifier: Modifier = Modifier,
) {
    val active = tasks.filter { it.stats.state.isActive }
    val totalDown = active.sumOf { it.stats.downloadRateBytesPerSec }
    val totalUp = active.sumOf { it.stats.uploadRateBytesPerSec }

    Column(modifier = modifier.fillMaxSize()) {
        when (engineStatus) {
            EngineStatus.FAILED -> InlineNotice(
                "The torrent engine could not start on this device. Downloads are unavailable; the reader and subscriptions still work.",
                isError = true,
            )
            EngineStatus.STARTING -> InlineNotice("Starting the torrent engine…")
            EngineStatus.STOPPED -> InlineNotice("The torrent engine is stopped.")
            EngineStatus.RUNNING -> Unit
        }

        if (settings.wifiOnlyDownloads) {
            InlineNotice("Wi-Fi only: transfers are paused on metered networks.")
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Active transfers", style = MaterialTheme.typography.titleMedium)
                        Text("${active.size} active", style = MaterialTheme.typography.bodyMedium)
                        Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                            Text("↓ ${Format.rate(totalDown)}", style = MaterialTheme.typography.bodyMedium)
                            Text("↑ ${Format.rate(totalUp)}", style = MaterialTheme.typography.bodyMedium)
                        }
                        Text(
                            "Background transfers depend on Android's battery rules; " +
                                "they may stop if the system or the manufacturer's power manager ends them.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            item {
                Text("Recent activity", style = MaterialTheme.typography.titleSmall)
            }

            if (tasks.isEmpty() && library.isEmpty()) {
                item {
                    EmptyState(
                        title = "Nothing here yet",
                        message = "Add a magnet link or a .torrent file to start downloading, or add a book to the library.",
                    )
                }
            } else {
                items(tasks.take(3), key = { it.id }) { task ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(14.dp)) {
                            Text(Format.truncateMiddle(task.displayName), style = MaterialTheme.typography.bodyLarge)
                            Text(
                                "${stateLabel(task)} • ${Format.percent(task.stats.percent)}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                items(library.take(3), key = { it.id }) { item ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(14.dp)) {
                            Text(Format.truncateMiddle(item.title), style = MaterialTheme.typography.bodyLarge)
                            Text(item.kind.name, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }
    }
}

private fun stateLabel(task: TorrentTaskRecord): String = when {
    task.stats.state.isActive -> "Active"
    else -> task.stats.state.name.lowercase().replaceFirstChar { it.uppercase() }
}
