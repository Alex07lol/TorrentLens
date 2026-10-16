package dev.torrentlens.torrentlens

import dev.torrentlens.torrentlens.torrent.TorrentEnginePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers the native torrent engine plugin.
 *
 * The Flutter side owns the UI, persistence and the network integrations; this
 * Activity only wires the Kotlin services layer into the engine.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(TorrentEnginePlugin())
        flutterEngine.plugins.add(SystemSharePlugin())
    }
}
