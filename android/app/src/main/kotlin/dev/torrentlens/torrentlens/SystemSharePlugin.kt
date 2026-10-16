package dev.torrentlens.torrentlens

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The tiny bit of Android the browser chrome needs: handing a URL to the system
 * share sheet.
 *
 * It is a method channel rather than a plugin dependency because this is the
 * only platform call the UI needs, and the app already ships a native layer.
 * Everything it accepts is a plain string; nothing is logged, and no file is
 * ever written to a shared location.
 */
class SystemSharePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "share" -> share(call, result)
            else -> result.notImplemented()
        }
    }

    private fun share(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")
        if (text.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Nothing to share.", null)
            return
        }
        val ctx = context
        if (ctx == null) {
            result.error("NO_CONTEXT", "The Android context is not available.", null)
            return
        }
        val subject = call.argument<String>("subject")
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            if (!subject.isNullOrBlank()) putExtra(Intent.EXTRA_SUBJECT, subject)
        }
        val chooser = Intent.createChooser(send, subject ?: "Share").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            ctx.startActivity(chooser)
            result.success(null)
        } catch (e: Exception) {
            // e.g. a device image with no handler for text/plain.
            result.error("NO_TARGET", e.message ?: "No app can handle sharing.", null)
        }
    }

    companion object {
        const val CHANNEL = "dev.torrentlens/system"
    }
}
