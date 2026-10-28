package expo.modules.tinkerloomdevice

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Handler
import android.os.Looper
import android.os.Vibrator
import android.view.Window
import android.view.WindowManager
import androidx.core.content.ContextCompat
import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.functions.Queues
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.lang.ref.WeakReference

class TinkerloomDeviceModule : Module() {
  private var lease: String? = null
  private var foreground = false
  private var ownsTorch = false
  private var torchAvailable = true
  private var previousBrightness: Float? = null
  private var previousAwake: Boolean? = null
  private var controlledWindow: WeakReference<Window>? = null
  private val main = Handler(Looper.getMainLooper())
  private data class TorchRequest(val enabled: Boolean, val promise: Promise)
  private var pending: TorchRequest? = null
  private val context get() = appContext.reactContext ?: throw failure("inactive")
  private val camera get() = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
  private val torchId: String? get() = try {
    camera.cameraIdList.firstOrNull { id ->
      val info = camera.getCameraCharacteristics(id)
      info.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true &&
        info.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
    }
  } catch (_: Exception) { null }
  private fun failure(code: String) = CodedException(code, "The device request could not be completed.", null)
  private val callback = object : CameraManager.TorchCallback() {
    override fun onTorchModeChanged(id: String, enabled: Boolean) {
      if (id != torchId) return
      torchAvailable = true
      pending?.takeIf { it.enabled == enabled }?.let { pending = null; ownsTorch = enabled; it.promise.resolve(null) }
    }
    override fun onTorchModeUnavailable(id: String) {
      if (id != torchId) return
      torchAvailable = false
      pending?.let { pending = null; it.promise.reject(failure("unavailable")) }
    }
  }
  private fun claim(token: String) {
    if (token.isEmpty() || token.length > 128) throw failure("invalid")
    if (!foreground || appContext.currentActivity?.hasWindowFocus() != true) throw failure("inactive")
    if (lease != token) { releaseAll(); lease = token }
  }
  override fun definition() = ModuleDefinition {
    Name("TinkerloomDevice")
    OnCreate {
      foreground = appContext.currentActivity?.hasWindowFocus() == true
      try { camera.registerTorchCallback(callback, main) } catch (_: Exception) { torchAvailable = false }
    }
    OnActivityEntersForeground { foreground = true }
    OnActivityEntersBackground { foreground = false; releaseAll() }
    OnActivityDestroys { foreground = false; releaseAll() }
    OnDestroy { releaseAll(); try { camera.unregisterTorchCallback(callback) } catch (_: Exception) {} }
    AsyncFunction("availability") {
      val flashlight = try { torchId != null && torchAvailable } catch (_: Exception) { false }
      @Suppress("DEPRECATION")
      val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
      mapOf("flashlight" to flashlight, "brightness" to (appContext.currentActivity != null),
        "keepAwake" to (appContext.currentActivity != null), "haptics" to (vibrator?.hasVibrator() == true))
    }.runOnQueue(Queues.MAIN)
    AsyncFunction("setTorch") { enabled: Boolean, token: String, promise: Promise ->
      claim(token)
      val id = torchId ?: throw failure("unavailable")
      if (!torchAvailable || pending != null) throw failure("unavailable")
      if (enabled && ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) throw failure("permission_denied")
      if (!enabled && !ownsTorch) { promise.resolve(null); return@AsyncFunction }
      val request = TorchRequest(enabled, promise)
      pending = request
      ownsTorch = enabled || ownsTorch
      try { camera.setTorchMode(id, enabled) }
      catch (_: Exception) { pending = null; promise.reject(failure("unavailable")); reset("flashlight"); return@AsyncFunction }
      main.postDelayed({
        if (pending === request) { pending = null; request.promise.reject(failure("unavailable")); reset("flashlight") }
      }, 2500)
    }.runOnQueue(Queues.MAIN)
    AsyncFunction("setBrightness") { value: Double?, token: String ->
      claim(token)
      if (value == null) { reset("brightness"); return@AsyncFunction }
      if (!value.isFinite() || value < 0 || value > 1) throw failure("invalid")
      val window = appContext.currentActivity?.window ?: throw failure("inactive")
      if (previousBrightness == null) { previousBrightness = window.attributes.screenBrightness; controlledWindow = WeakReference(window) }
      window.attributes = window.attributes.apply { screenBrightness = value.toFloat() }
    }.runOnQueue(Queues.MAIN)
    AsyncFunction("setKeepAwake") { enabled: Boolean, token: String ->
      claim(token)
      val window = appContext.currentActivity?.window ?: throw failure("inactive")
      if (enabled) {
        if (previousAwake == null) { previousAwake = window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0; controlledWindow = WeakReference(window) }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      } else reset("keepAwake")
    }.runOnQueue(Queues.MAIN)
    AsyncFunction("release") { control: String, token: String ->
      if (control !in listOf("flashlight", "brightness", "keepAwake", "haptics")) throw failure("invalid")
      if (lease == token && !reset(control)) throw failure("unavailable")
    }.runOnQueue(Queues.MAIN)
  }
  private fun reset(control: String): Boolean {
    var released = true
    if (control == "flashlight") {
      pending?.let { pending = null; it.promise.reject(failure("inactive")) }
      if (ownsTorch) try { val id = torchId ?: throw failure("unavailable"); camera.setTorchMode(id, false); ownsTorch = false } catch (_: Exception) { released = false }
    }
    val window = controlledWindow?.get()
    if (control == "brightness") { previousBrightness?.let { original -> window?.let { it.attributes = it.attributes.apply { screenBrightness = original } } }; previousBrightness = null }
    if (control == "keepAwake") { previousAwake?.let { original -> if (original) window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) else window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }; previousAwake = null }
    if (previousBrightness == null && previousAwake == null) controlledWindow = null
    return released
  }
  private fun releaseAll() {
    listOf("flashlight", "brightness", "keepAwake").forEach { reset(it) }
    if (!ownsTorch) lease = null
  }
}
