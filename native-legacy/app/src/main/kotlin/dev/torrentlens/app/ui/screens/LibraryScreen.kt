package dev.torrentlens.app.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.torrentlens.app.ui.Format
import dev.torrentlens.app.ui.components.EmptyState
import dev.torrentlens.core.domain.model.LibraryItem
import dev.torrentlens.core.domain.model.MediaKind
import dev.torrentlens.core.reader.ReaderFormatDetector
import java.util.UUID

@Composable
fun LibraryScreen(
    items: List<LibraryItem>,
    onAdd: (LibraryItem) -> Unit,
    onOpen: (LibraryItem) -> Unit,
    onRemove: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: "document"
            val kind = ReaderFormatDetector.detect(name)
            onAdd(
                LibraryItem(
                    id = UUID.randomUUID().toString(),
                    title = name,
                    kind = kind,
                    contentUri = uri.toString(),
                    sizeBytes = 0,
                    addedAtEpochMillis = System.currentTimeMillis(),
                ),
            )
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        Button(
            onClick = {
                picker.launch(
                    arrayOf(
                        "application/epub+zip",
                        "application/pdf",
                        "application/vnd.comicbook+zip",
                        "application/x-cbr",
                        "text/plain",
                        "image/*",
                        "*/*",
                    ),
                )
            },
            modifier = Modifier.fillMaxWidth().padding(16.dp),
        ) { Text("Add a document") }

        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (items.isEmpty()) {
                item {
                    EmptyState(
                        title = "Your library is empty",
                        message = "Add EPUB books, PDFs, CBZ/CBR comics, images or text files. " +
                            "Files are read through the Storage Access Framework — no storage permission is needed.",
                    )
                }
            } else {
                items(items, key = { it.id }) { item ->
                    Card(modifier = Modifier.fillMaxWidth().clickable { onOpen(item) }) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(14.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(Format.truncateMiddle(item.title, 36), style = MaterialTheme.typography.bodyLarge)
                                Text(
                                    "${readableKind(item.kind)} • added ${Format.relativeAge(item.addedAtEpochMillis)}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            TextButton(onClick = { onRemove(item.id) }) { Text("Remove") }
                        }
                    }
                }
            }
        }
    }
}

private fun readableKind(kind: MediaKind): String = when (kind) {
    MediaKind.EPUB -> "EPUB book"
    MediaKind.PDF -> "PDF document"
    MediaKind.CBZ -> "CBZ comic"
    MediaKind.CBR -> "CBR comic (UnRAR licence)"
    MediaKind.IMAGE -> "Image"
    MediaKind.TEXT -> "Text"
    MediaKind.HTML_BUNDLE -> "Site bundle"
    MediaKind.UNKNOWN -> "Unsupported"
}
