package com.sirfhum.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Platform key store for the crypto core (D-066). App-owned channel,
        // not a third-party plugin (KEY-MANAGEMENT.md §3, option a).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SecureKeyStore.CHANNEL)
            .setMethodCallHandler(SecureKeyStore(applicationContext))
        // Only the cache path: the photo-picker sweep itself is Dart, where
        // it is unit-tested (P2-3, D-141; picker_cache_sweeper.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CACHE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "cacheDirectory") {
                    result.success(applicationContext.cacheDir.absolutePath)
                } else {
                    result.notImplemented()
                }
            }
        // The system share sheet for a pairing invitation. App-owned, so no
        // share plugin (and its dependencies) for one plain-text intent.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                val text = call.argument<String>("text")
                if (call.method != "shareText" || text == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val send = Intent(Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, text)
                startActivity(Intent.createChooser(send, null))
                result.success(null)
            }
    }

    private companion object {
        const val APP_CACHE_CHANNEL = "com.sirfhum.app/app_cache"
        const val SHARE_CHANNEL = "com.sirfhum.app/share"
    }
}
