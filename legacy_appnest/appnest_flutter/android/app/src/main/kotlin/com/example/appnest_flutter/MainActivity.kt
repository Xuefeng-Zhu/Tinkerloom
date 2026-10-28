package com.example.appnest_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var device: DeviceCapabilitiesBridge? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        device = DeviceCapabilitiesBridge(this, engine.dartExecutor.binaryMessenger)
    }
    override fun onResume() { super.onResume(); device?.resume() }
    override fun onPause() { device?.pause(); super.onPause() }
    override fun onDestroy() { device?.dispose(); super.onDestroy() }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (device?.permissionResult(requestCode, grantResults) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
