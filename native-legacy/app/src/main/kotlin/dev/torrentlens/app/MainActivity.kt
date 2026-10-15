package dev.torrentlens.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.torrentlens.app.ui.TorrentLensApp
import dev.torrentlens.app.ui.TorrentLensViewModel
import dev.torrentlens.app.ui.theme.TorrentLensTheme

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as TorrentLensApplication).container
        // A magnet link or .torrent opened from another app arrives as intent data.
        val incoming = intent?.dataString

        setContent {
            val viewModel: TorrentLensViewModel = viewModel(
                factory = TorrentLensViewModel.factory(container),
            )
            val settings by viewModel.settings.collectAsStateWithLifecycle()
            TorrentLensTheme(darkTheme = settings.themeDark) {
                TorrentLensApp(
                    viewModel = viewModel,
                    cacheRoot = container.cacheRoot,
                    initialImportText = incoming,
                )
            }
        }
    }
}
