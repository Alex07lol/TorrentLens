package dev.torrentlens.app.ui.import

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.torrentlens.app.R

/**
 * The torrent import sheet: pasted magnet/URL, a picked `.torrent` file, and the
 * user's chosen download folder — all three in one place.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ImportSheet(
    initialText: String?,
    onDismiss: () -> Unit,
    onImportText: (String) -> Unit,
    onPickedTorrent: (displayName: String, location: String) -> Unit,
    onFolderChosen: (uri: String) -> Unit,
    currentFolder: String?,
    isBusy: Boolean,
) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var text by remember { mutableStateOf(initialText.orEmpty()) }

    LaunchedEffect(initialText) { if (!initialText.isNullOrBlank()) text = initialText }

    val torrentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            // Keep read access across process death; without this the task cannot
            // re-read the descriptor after a restart.
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: "imported.torrent"
            onPickedTorrent(name, uri.toString())
            onDismiss()
        }
    }

    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
            onFolderChosen(uri.toString())
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Add a torrent", style = MaterialTheme.typography.titleLarge)

            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                label = { Text(stringResourceSafe(R.string.import_hint)) },
                minLines = 2,
                maxLines = 4,
                modifier = Modifier.fillMaxWidth(),
            )

            Button(
                onClick = { onImportText(text.trim()); onDismiss() },
                enabled = text.isNotBlank() && !isBusy,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Add magnet or URL") }

            OutlinedButton(
                onClick = { torrentPicker.launch(arrayOf("application/x-bittorrent", "*/*")) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Pick a .torrent file") }

            Text("Download folder", style = MaterialTheme.typography.titleSmall)
            Text(
                currentFolder ?: "Using app storage (no permission needed)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedButton(
                onClick = { folderPicker.launch(null) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Choose folder") }

            Text(
                "Chosen folders are accessed through the Storage Access Framework. " +
                    "TorrentLens never requests full storage access.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 16.dp),
            )
        }
    }
}

@Composable
private fun stringResourceSafe(id: Int): String = androidx.compose.ui.res.stringResource(id)
