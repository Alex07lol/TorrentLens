package dev.torrentlens.app

import android.app.Application
import dev.torrentlens.app.di.AppContainer

/**
 * Process entry point. The container is built once here and handed to the UI
 * through a ViewModel factory — see ADR 0007 for why the graph is wired by hand
 * instead of with an annotation-based DI framework.
 */
class TorrentLensApplication : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this).also { it.bootstrap() }
    }
}
