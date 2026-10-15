package dev.torrentlens.app.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.torrentlens.app.ui.Format
import dev.torrentlens.core.data.repo.TorrentTaskRecord
import dev.torrentlens.core.domain.model.TorrentTaskState

@Composable
fun TaskCard(
    task: TorrentTaskRecord,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onRemove: () -> Unit,
    onSelectFiles: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val stats = task.stats
    Card(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                Format.truncateMiddle(task.displayName),
                style = MaterialTheme.typography.titleSmall,
            )
            Text(
                text = stateLabel(stats.state) + " • " + Format.percent(stats.percent),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            LinearProgressIndicator(
                progress = { stats.progress.toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("↓ ${Format.rate(stats.downloadRateBytesPerSec)}", style = MaterialTheme.typography.bodySmall)
                Text("↑ ${Format.rate(stats.uploadRateBytesPerSec)}", style = MaterialTheme.typography.bodySmall)
                Text("${stats.numPeers} peers", style = MaterialTheme.typography.bodySmall)
                Text("${stats.numSeeds} seeds", style = MaterialTheme.typography.bodySmall)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    "${Format.size(stats.downloadedBytes)} / ${Format.size(stats.totalBytes)}",
                    style = MaterialTheme.typography.bodySmall,
                )
                Text("ETA ${Format.eta(stats.etaSeconds)}", style = MaterialTheme.typography.bodySmall)
            }

            val errorMessage = stats.errorMessage
            if (errorMessage != null) {
                Text(
                    errorMessage,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onSelectFiles) {
                    Icon(Icons.Filled.List, contentDescription = "Select files")
                }
                if (stats.state == TorrentTaskState.PAUSED) {
                    IconButton(onClick = onResume) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = "Resume")
                    }
                } else {
                    IconButton(onClick = onPause) {
                        Icon(Icons.Filled.Pause, contentDescription = "Pause")
                    }
                }
                IconButton(onClick = onRemove) {
                    Icon(Icons.Filled.Delete, contentDescription = "Remove")
                }
            }
        }
    }
}

fun stateLabel(state: TorrentTaskState): String = when (state) {
    TorrentTaskState.METADATA -> "Fetching metadata"
    TorrentTaskState.QUEUED -> "Queued"
    TorrentTaskState.DOWNLOADING -> "Downloading"
    TorrentTaskState.SEEDING -> "Seeding"
    TorrentTaskState.PAUSED -> "Paused"
    TorrentTaskState.COMPLETE -> "Complete"
    TorrentTaskState.ERROR -> "Error"
}
