package dev.torrentlens.core.reader

import android.annotation.SuppressLint
import android.webkit.WebSettings
import android.webkit.WebView

/**
 * Hardening for the only component that executes remote markup: the web view
 * used for EPUB chapters and downloaded static site bundles.
 *
 * Downloaded HTML is untrusted. It must not be able to reach app-private files,
 * `content://` providers, the `file://` namespace, or any JavaScript bridge.
 * JavaScript is therefore off unless a caller explicitly opts in, and no
 * `addJavascriptInterface` bridge is ever installed.
 */
object IsolatedWebView {

    @SuppressLint("SetJavaScriptEnabled")
    fun apply(view: WebView, allowJavaScript: Boolean = false) {
        view.settings.apply {
            javaScriptEnabled = allowJavaScript
            // No local or cross-origin filesystem access of any kind.
            allowFileAccess = false
            allowContentAccess = false
            @Suppress("DEPRECATION")
            allowFileAccessFromFileURLs = false
            @Suppress("DEPRECATION")
            allowUniversalAccessFromFileURLs = false
            // Block mixed content and third-party storage access.
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            domStorageEnabled = false
            databaseEnabled = false
            setGeolocationEnabled(false)
            mediaPlaybackRequiresUserGesture = true
            // Do not advertise the app or its version to page content.
            userAgentString = "TorrentLensReader"
            cacheMode = WebSettings.LOAD_CACHE_ELSE_NETWORK
            // Text sizing is controlled by the reader UI, not the page.
            textZoom = 100
        }
        view.isVerticalScrollBarEnabled = true
        // Long-press selection is useful for reading; text-to-speech piping is not
        // enabled here because it would need a JS bridge.
        view.setOnLongClickListener { false }
    }

    /** Wraps a chapter body into a minimal, self-contained document. */
    fun wrapChapter(
        bodyHtml: String,
        css: String = "",
        darkTheme: Boolean = false,
        fontSizePercent: Int = 100,
        direction: ReadingDirectionCss = ReadingDirectionCss.LEFT_TO_RIGHT,
    ): String {
        val background = if (darkTheme) "#121212" else "#ffffff"
        val foreground = if (darkTheme) "#e6e6e6" else "#111111"
        return """
            <!DOCTYPE html>
            <html dir="${direction.css}" style="direction:${direction.css}">
            <head>
              <meta charset="utf-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0" />
              <style>
                :root { color-scheme: ${if (darkTheme) "dark" else "light"}; }
                html, body { margin:0; padding:0; background:$background; color:$foreground; }
                body {
                  font-family: system-ui, -apple-system, "Noto Serif", serif;
                  font-size: ${fontSizePercent}%;
                  line-height: 1.55;
                  padding: 16px 18px 48px 18px;
                  word-wrap: break-word;
                  -webkit-text-size-adjust: 100%;
                }
                img, svg, video { max-width: 100%; height: auto; }
                pre { white-space: pre-wrap; }
                a { color: ${if (darkTheme) "#8ab4f8" else "#1a5fb4"}; }
                $css
              </style>
            </head>
            <body>$bodyHtml</body>
            </html>
        """.trimIndent()
    }
}

enum class ReadingDirectionCss(val css: String) {
    LEFT_TO_RIGHT("ltr"),
    RIGHT_TO_LEFT("rtl"),
}
