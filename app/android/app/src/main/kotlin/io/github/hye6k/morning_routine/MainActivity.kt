package io.github.hye6k.morning_routine

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var platform: MorningPlatform? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        platform = MorningPlatform(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onResume() {
        super.onResume()
        platform?.onResume()
    }
    override fun onPause() {
        platform?.onPause()
        super.onPause()
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        platform?.close()
        platform = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
