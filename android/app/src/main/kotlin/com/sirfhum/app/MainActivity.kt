package com.sirfhum.app

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
    }
}
