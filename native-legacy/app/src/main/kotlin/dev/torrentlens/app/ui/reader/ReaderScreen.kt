package dev.torrentlens.app.ui.reader

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.BookmarkAdd
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import android.webkit.WebView
import androidx.compose.foundation.Image
import dev.torrentlens.app.data.ReaderContentLoader
import dev.torrentlens.core.domain.model.LibraryItem
import dev.torrentlens.core.domain.model.ReadingDirection
import dev.torrentlens.core.domain.model.ReadingMode
import dev.torrentlens.core.reader.ComicArchive
import dev.torrentlens.core.reader.IsolatedWebView
import dev.torrentlens.core.reader.PdfPageSource
import dev.torrentlens.core.reader.ReadingDirectionCss
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

private sealed interface ReaderUiState {
    data object Loading : ReaderUiState
    data class Ready(val content: ReaderContentLoader.Content) : ReaderUiState
    data class Failed(val message: String) : ReaderUiState
}

/**
 * The touch-first reader. Chapter/page navigation, dark/light rendering, RTL
 * manga direction and both paged and scrolling layouts are chosen from the
 * library item's kind plus the user's reading defaults.
 */
@Composable
fun ReaderScreen(
    item: LibraryItem,
    cacheRoot: File,
    defaultMode: ReadingMode,
    defaultDirection: ReadingDirection,
    onBack: () -> Unit,
    onSaveProgress: (locator: String, percent: Double, mode: ReadingMode, direction: ReadingDirection) -> Unit,
    onAddBookmark: (locator: String) -> Unit,
) {
    val context = LocalContext.current
    val loader = remember { ReaderContentLoader(context, cacheRoot) }
    var state by remember(item.id) { mutableStateOf<ReaderUiState>(ReaderUiState.Loading) }
    val direction = defaultDirection

    LaunchedEffect(item.id) {
        state = ReaderUiState.Loading
        loader.load(item)
            .onSuccess { state = ReaderUiState.Ready(it) }
            .onFailure { state = ReaderUiState.Failed(it.message ?: "This document could not be opened.") }
    }

    DisposableEffect(item.id) {
        onDispose {
            when (val current = state) {
                is ReaderUiState.Ready -> when (val content = current.content) {
                    is ReaderContentLoader.ComicContent -> runCatching { content.archive.close() }
                    is ReaderContentLoader.PdfContent -> runCatching { content.source.close() }
                    is ReaderContentLoader.EpubContent -> runCatching { content.publication.close() }
                    else -> Unit
                }
                else -> Unit
            }
        }
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
            }
            Text(
                text = readerTitle(state) ?: item.title,
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = { onAddBookmark(currentLocator(state)) }) {
                Icon(Icons.Filled.BookmarkAdd, contentDescription = "Add bookmark")
            }
        }

        when (val current = state) {
            is ReaderUiState.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }

            is ReaderUiState.Failed -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Cannot open this document", style = MaterialTheme.typography.titleSmall)
                    Text(
                        current.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }

            is ReaderUiState.Ready -> when (val content = current.content) {
                is ReaderContentLoader.ComicContent -> PagedImages(
                    pageCount = content.archive.pageCount,
                    reverse = direction == ReadingDirection.RIGHT_TO_LEFT,
                    onPageChanged = { page, total ->
                        onSaveProgress(page.toString(), (page + 1).toDouble() / total, defaultMode, direction)
                    },
                    load = { page -> loadComicPage(content.archive, page) },
                )

                is ReaderContentLoader.PdfContent -> {
                    val configuration = LocalConfiguration.current
                    val density = LocalDensity.current
                    val targetWidth = with(density) { configuration.screenWidthDp.dp.roundToPx() }
                    PagedImages(
                        pageCount = content.source.pageCount,
                        reverse = direction == ReadingDirection.RIGHT_TO_LEFT,
                        onPageChanged = { page, total ->
                            onSaveProgress(page.toString(), (page + 1).toDouble() / total, defaultMode, direction)
                        },
                        load = { page -> loadPdfPage(content.source, page, targetWidth) },
                    )
                }

                is ReaderContentLoader.TextContent -> TextPages(
                    pages = content.source.pages,
                    onPageChanged = { page, total ->
                        onSaveProgress(page.toString(), (page + 1).toDouble() / total, defaultMode, direction)
                    },
                )

                is ReaderContentLoader.ImageContent -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Image(
                        bitmap = content.bitmap.asImageBitmap(),
                        contentDescription = item.title,
                        modifier = Modifier.fillMaxSize().padding(4.dp),
                        contentScale = ContentScale.Fit,
                    )
                }

                is ReaderContentLoader.EpubContent -> EpubChapters(
                    publication = content.publication,
                    rtl = direction == ReadingDirection.RIGHT_TO_LEFT,
                    onChapterChanged = { chapter, total ->
                        val href = content.publication.spineHrefs.getOrElse(chapter) { "" }
                        onSaveProgress(href, (chapter + 1).toDouble() / total, defaultMode, direction)
                    },
                )
            }
        }
    }
}

@Composable
private fun PagedImages(
    pageCount: Int,
    reverse: Boolean,
    onPageChanged: (page: Int, total: Int) -> Unit,
    load: suspend (Int) -> Bitmap?,
) {
    if (pageCount <= 0) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("No pages found.") }
        return
    }
    val pagerState = rememberPagerState(pageCount = { pageCount })
    LaunchedEffect(pagerState.currentPage) {
        onPageChanged(pagerState.currentPage, pageCount)
    }
    HorizontalPager(state = pagerState, reverseLayout = reverse, modifier = Modifier.fillMaxSize()) { page ->
        val bitmap by produceState<Bitmap?>(initialValue = null, page) {
            value = withContext(Dispatchers.IO) { runCatching { load(page) }.getOrNull() }
        }
        val current = bitmap
        if (current == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else {
            Image(
                bitmap = current.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Fit,
            )
        }
    }
}

@Composable
private fun TextPages(pages: List<String>, onPageChanged: (page: Int, total: Int) -> Unit) {
    val pagerState = rememberPagerState(pageCount = { pages.size })
    LaunchedEffect(pagerState.currentPage) { onPageChanged(pagerState.currentPage, pages.size) }
    HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
        val scroll = rememberScrollState()
        Text(
            text = pages.getOrElse(page) { "" },
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.fillMaxSize().verticalScroll(scroll).padding(16.dp),
        )
    }
}

@Composable
private fun EpubChapters(
    publication: dev.torrentlens.core.reader.EpubPublication,
    rtl: Boolean,
    onChapterChanged: (chapter: Int, total: Int) -> Unit,
) {
    var chapter by remember { mutableIntStateOf(0) }
    val total = publication.chapterCount
    val href = publication.spineHrefs.getOrElse(chapter) { "" }
    val html by produceState(initialValue = "", href) {
        value = withContext(Dispatchers.IO) {
            val raw = publication.readText(href).orEmpty()
            IsolatedWebView.wrapChapter(
                bodyHtml = raw,
                darkTheme = false,
                direction = if (rtl) ReadingDirectionCss.RIGHT_TO_LEFT else ReadingDirectionCss.LEFT_TO_RIGHT,
            )
        }
    }

    LaunchedEffect(chapter) { onChapterChanged(chapter, total) }

    Column(Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxWidth().weight(1f),
            factory = { context ->
                WebView(context).apply { IsolatedWebView.apply(this, allowJavaScript = false) }
            },
            update = { web -> web.loadDataWithBaseURL("about:blank", html, "text/html", "utf-8", null) },
        )
        Row(
            modifier = Modifier.fillMaxWidth().padding(8.dp),
            horizontalArrangement = if (rtl) Arrangement.End else Arrangement.Start,
        ) {
            TextButton(onClick = { if (chapter > 0) chapter-- }, enabled = chapter > 0) { Text("Previous") }
            Text(
                " ${chapter + 1} / $total ",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
            TextButton(onClick = { if (chapter < total - 1) chapter++ }, enabled = chapter < total - 1) {
                Text("Next")
            }
        }
    }
}

private suspend fun loadComicPage(archive: ComicArchive, page: Int): Bitmap? {
    val bytes = archive.readPage(page)
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
}

private suspend fun loadPdfPage(source: PdfPageSource, page: Int, targetWidth: Int): Bitmap =
    source.render(page, targetWidth)

private fun readerTitle(state: ReaderUiState): String? =
    (state as? ReaderUiState.Ready)?.content?.title

private fun currentLocator(state: ReaderUiState): String = when (val current = state) {
    is ReaderUiState.Ready -> when (val content = current.content) {
        is ReaderContentLoader.EpubContent -> content.publication.spineHrefs.firstOrNull().orEmpty()
        else -> "0"
    }
    else -> "0"
}
