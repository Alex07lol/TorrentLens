package dev.torrentlens.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.torrentlens.app.ui.Format
import dev.torrentlens.app.ui.components.EmptyState
import dev.torrentlens.app.ui.components.TaskCard
import dev.torrentlens.core.data.repo.TorrentTaskRecord
import dev.torrentlens.core.domain.model.SelectedFile

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadsScreen(
    tasks: List<TorrentTaskRecord>,
    selectedTask: TorrentTaskRecord?,
    files: List<SelectedFile>,
    onPause: (String) -> Unit,
    onResume: (String) -> Unit,
    onRemove: (String) -> Unit,
    onOpenFiles: (String?) -> Unit,
    onToggleFile: (taskId: String, path: String, selected: Boolean) -> Unit,
    onApplySelection: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (tasks.isEmpty()) {
            item {
                EmptyState(
                    title = "No downloads",
                    message = "Add a magnet link, a torrent URL, or a .torrent file from the dashboard.",
                )
            }
        } else {
            items(tasks, key = { it.id }) { task ->
                TaskCard(
                    task = task,
                    onPause = { onPause(task.id) },
                    onResume = { onResume(task.id) },
                    onRemove = { onRemove(task.id) },
                    onSelectFiles = { onOpenFiles(task.id) },
                )
            }
        }
    }

    if (selectedTask != null && files.isNotEmpty()) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { onOpenFiles(null) }, sheetState = sheetState) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                Text("Files in ${Format.truncateMiddle(selectedTask.displayName, 32)}", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Unselected files are not downloaded. Deselected files already on disk are left in place.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                LazyColumn(modifier = Modifier.weight(1f, fill = false)) {
                    items(files, key = { it.relativePath }) { file ->
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                            Checkbox(
                                checked = file.selected,
                                onCheckedChange = { checked -> onToggleFile(selectedTask.id, file.relativePath, checked) },
                            )
                            Column(Modifier.weight(1f)) {
                                Text(Format.truncateMiddle(file.relativePath, 40), style = MaterialTheme.typography.bodyMedium)
                                Text(Format.size(file.sizeBytes), style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = { onApplySelection(selectedTask.id) }) { Text("Apply selection") }
                }
            }
        }
    }
}
