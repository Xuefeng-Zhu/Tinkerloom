package com.example.appnest_flutter

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Vibrator
import android.os.Looper
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.TimeZone

/** Only this fixed bridge can access hardware; definitions cannot name native APIs. */
class DeviceCapabilitiesBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val channel = MethodChannel(messenger, "appnest/device")
    private val events = EventChannel(messenger, "appnest/device/events")
    private val main = Handler(Looper.getMainLooper())
    private val camera = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val connectivity = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var session: String? = null
    private var grants = emptySet<String>()
    private var foreground = false
    private var sink: EventChannel.EventSink? = null
    private var batteryReceiver: BroadcastReceiver? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var torchRegistered = false
    private var torchOn = false
    private var ownsTorch = false
    private var torchAvailable = true
    private var previousBrightness: Float? = null
    private var previousAwake: Boolean? = null
    private var pendingPermission: Pair<String, MethodChannel.Result>? = null
    private val capabilities = setOf("battery", "device", "connection", "locale", "flashlight", "brightness", "keepAwake", "haptics")
    private val torchId: String? by lazy {
        try { camera.cameraIdList.firstOrNull { id ->
            val info = camera.getCameraCharacteristics(id)
            info.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true &&
                info.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        } } catch (_: Exception) { null }
    }
    private val torchCallback = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(id: String, enabled: Boolean) {
            if (id == torchId) { torchOn = enabled; torchAvailable = true; changed() }
        }
        override fun onTorchModeUnavailable(id: String) {
            if (id == torchId) { torchOn = false; torchAvailable = false; changed() }
        }
    }
    init { channel.setMethodCallHandler(this); events.setStreamHandler(this) }
    fun resume() { foreground = true; changed() }
    fun pause() { foreground = false; release() }
    fun dispose() {
        release()
        pendingPermission?.second?.error("inactive", "Request interrupted", null)
        pendingPermission = null
        channel.setMethodCallHandler(null); events.setStreamHandler(null)
    }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
    override fun onCancel(arguments: Any?) { sink = null }
    private fun changed() { main.post { sink?.success(null) } }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val token = call.argument<String>("session")
            if (token.isNullOrEmpty()) { result.error("invalid", "Missing session", null); return }
            if (call.method == "release") {
                if (token == session) release()
                result.success(null); return
            }
            if (!foreground) { result.error("inactive", "Phone app is not active", null); return }
            if (call.method == "configure") {
                val requested = call.argument<List<String>>("grants")?.toSet() ?: emptySet()
                if (!capabilities.containsAll(requested)) { result.error("invalid", "Unknown capability", null); return }
                if (session != token) { release(); session = token }
                if (requested != grants) {
                    for (removed in grants - requested) reset(removed)
                    stopMonitoring(); grants = requested; startMonitoring()
                }
                result.success(null); return
            }
            if (token != session) { result.error("inactive", "Session is no longer active", null); return }
            when (call.method) {
                "query" -> result.success(snapshot())
                "settings" -> {
                    activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
                    result.success(null)
                }
                "command" -> {
                    val control = call.argument<String>("control") ?: ""
                    if (!grants.contains(control)) { result.error("permissionDenied", "Access is off", null); return }
                    val value = call.argument<Any>("value")
                    when (control) {
                        "flashlight" -> {
                            if (value !is Boolean) { result.error("invalid", "Expected boolean", null); return }
                            val id = torchId
                            if (id == null || !torchAvailable) { result.error("unavailable", "Flashlight unavailable", null); return }
                            if (value && activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                                if (pendingPermission != null) { result.error("unavailable", "Permission request pending", null); return }
                                pendingPermission = Pair(token, result)
                                activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), 7314)
                                return
                            }
                            camera.setTorchMode(id, value)
                            torchOn = value; ownsTorch = value
                        }
                        "brightness" -> {
                            if (value != null && (value !is Number || !value.toDouble().isFinite() || value.toDouble() !in 0.0..1.0)) {
                                result.error("invalid", "Brightness must be 0 to 1", null); return
                            }
                            if (value == null) reset(control) else {
                                if (previousBrightness == null) previousBrightness = activity.window.attributes.screenBrightness
                                val attributes = activity.window.attributes
                                attributes.screenBrightness = (value as Number).toFloat()
                                activity.window.attributes = attributes
                            }
                        }
                        "keepAwake" -> {
                            if (value !is Boolean) { result.error("invalid", "Expected boolean", null); return }
                            if (value) {
                                if (previousAwake == null) previousAwake = awake()
                                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else reset(control)
                        }
                        "haptics" -> {
                            if (!activity.window.decorView.performHapticFeedback(HapticFeedbackConstants.CONFIRM)) {
                                result.error("unavailable", "Haptics unavailable or disabled", null); return
                            }
                        }
                        else -> { result.error("invalid", "Unknown control", null); return }
                    }
                    result.success(null); changed()
                }
                else -> result.notImplemented()
            }
        } catch (_: SecurityException) { result.error("permissionDenied", "OS permission denied", null) }
        catch (_: Exception) { result.error("unavailable", "Device feature unavailable", null) }
    }
    fun permissionResult(request: Int, permissions: IntArray): Boolean {
        if (request != 7314) return false
        val pending = pendingPermission ?: return true
        pendingPermission = null
        // A permission sheet interrupts the active session; never replay a hardware write.
        pending.second.error(if (permissions.firstOrNull() == PackageManager.PERMISSION_GRANTED) "inactive" else "permissionDenied",
            "Return to the mini-app and retry", null)
        return true
    }
    private fun awake() = activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0
    private fun snapshot(): Map<String, Any> {
        val values = mutableMapOf<String, Any>()
        if (grants.contains("battery")) {
            val battery = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level >= 0 && scale > 0) values["batteryLevel"] = level * 100 / scale
            values["charging"] = when (battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)) {
                BatteryManager.BATTERY_STATUS_CHARGING -> "Charging"
                BatteryManager.BATTERY_STATUS_FULL -> "Full"
                BatteryManager.BATTERY_STATUS_DISCHARGING, BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "Not charging"
                else -> "Unknown"
            }
        }
        if (grants.contains("device")) { values["model"] = "${Build.MANUFACTURER} ${Build.MODEL}"; values["osVersion"] = "Android ${Build.VERSION.RELEASE}" }
        if (grants.contains("locale")) {
            val locale = Locale.getDefault()
            values["language"] = locale.toLanguageTag(); values["region"] = locale.country.ifEmpty { "Unknown" }
            values["timeZone"] = TimeZone.getDefault().id
        }
        if (grants.contains("connection")) {
            val net = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
            values["connection"] = when {
                net == null -> "None"
                net.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
                net.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Cellular"
                else -> "Other"
            }
        }
        if (grants.contains("flashlight")) values["flashlight"] = torchOn
        if (grants.contains("keepAwake")) values["keepAwake"] = awake()
        if (grants.contains("brightness")) {
            val level = activity.window.attributes.screenBrightness
            values["brightness"] = if (level >= 0) level.toDouble() else Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255.0
        }
        return mapOf("values" to values, "availability" to capabilities.associateWith {
            if ((it == "flashlight" && (torchId == null || !torchAvailable)) ||
                (it == "haptics" && !(activity.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator).hasVibrator())) "unavailable" else "available"
        })
    }
    private fun startMonitoring() {
        if (grants.contains("battery")) {
            batteryReceiver = object : BroadcastReceiver() { override fun onReceive(context: Context?, intent: Intent?) { changed() } }
            activity.registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        }
        if (grants.contains("connection")) {
            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) { changed() }
                override fun onLost(network: Network) { changed() }
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) { changed() }
            }
            connectivity.registerDefaultNetworkCallback(networkCallback!!)
        }
        if (grants.contains("flashlight")) { camera.registerTorchCallback(torchCallback, main); torchRegistered = true }
    }
    private fun stopMonitoring() {
        batteryReceiver?.let { try { activity.unregisterReceiver(it) } catch (_: Exception) {} }; batteryReceiver = null
        networkCallback?.let { try { connectivity.unregisterNetworkCallback(it) } catch (_: Exception) {} }; networkCallback = null
        if (torchRegistered) camera.unregisterTorchCallback(torchCallback)
        torchRegistered = false
    }
    private fun reset(control: String) {
        when (control) {
            "flashlight" -> if (ownsTorch) {
                try { torchId?.let { camera.setTorchMode(it, false) } } catch (_: Exception) {}
                ownsTorch = false; torchOn = false
            }
            "brightness" -> previousBrightness?.let {
                val attributes = activity.window.attributes; attributes.screenBrightness = it
                activity.window.attributes = attributes; previousBrightness = null
            }
            "keepAwake" -> previousAwake?.let {
                if (!it) activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                previousAwake = null
            }
        }
    }
    private fun release() {
        stopMonitoring()
        for (control in listOf("flashlight", "brightness", "keepAwake")) reset(control)
        session = null; grants = emptySet()
    }
}
