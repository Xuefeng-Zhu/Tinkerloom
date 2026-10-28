import Flutter
import UIKit
import AVFoundation
import Network
import CoreHaptics

/// All commands are fixed native operations; mini-app definitions are never code.
final class DeviceCapabilitiesBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var session: String?
  private var grants = Set<String>()
  private let capabilities: Set<String> = ["battery", "device", "connection", "locale", "flashlight", "brightness", "keepAwake", "haptics"]
  private var sink: FlutterEventSink?
  private var foreground = UIApplication.shared.applicationState == .active
  private var monitor: NWPathMonitor?
  private var connection: String?
  private var previousBrightness: CGFloat?
  private weak var controlledScreen: UIScreen?
  private var previousAwake: Bool?
  private var previousBatteryMonitoring: Bool?
  private var ownsTorch = false
  private var torchObservation: NSKeyValueObservation?
  private var batteryObservers: [NSObjectProtocol] = []
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var pendingPermission = false
  private var torch: AVCaptureDevice? { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) }
  private var screen: UIScreen? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first(where: { $0.activationState == .foregroundActive })?.screen
  }
  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DeviceCapabilitiesBridge()
    let channel = FlutterMethodChannel(name: "appnest/device", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterEventChannel(name: "appnest/device/events", binaryMessenger: registrar.messenger()).setStreamHandler(instance)
  }
  override init() {
    super.init()
    lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.foreground = false; self?.release()
    })
    lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.foreground = true; self?.changed()
    })
  }
  deinit {
    release()
    lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
  private func changed() { DispatchQueue.main.async { [weak self] in self?.sink?(nil) } }
  private func fail(_ code: String, _ result: FlutterResult) { result(FlutterError(code: code, message: "Device request could not complete", details: nil)) }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let token = args["session"] as? String, !token.isEmpty else { fail("invalid", result); return }
    if call.method == "release" {
      if token == session { release() }; result(nil); return
    }
    guard foreground else { fail("inactive", result); return }
    if call.method == "configure" {
      guard let list = args["grants"] as? [String], Set(list).isSubset(of: capabilities) else { fail("invalid", result); return }
      let requested = Set(list)
      if session != token { release(); session = token }
      if grants != requested {
        for control in grants.subtracting(requested) { reset(control) }
        stopMonitoring(); grants = requested; startMonitoring()
      }
      result(nil); return
    }
    guard token == session else { fail("inactive", result); return }
    switch call.method {
    case "query": result(snapshot())
    case "settings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else { fail("unavailable", result); return }
      UIApplication.shared.open(url, options: [:]) { success in
        success ? result(nil) : self.fail("unavailable", result)
      }
    case "command":
      guard let control = args["control"] as? String, grants.contains(control) else { fail("permissionDenied", result); return }
      let value = args["value"]
      switch control {
      case "flashlight":
        guard let enabled = value as? Bool, let device = torch, device.hasTorch, device.isTorchAvailable else { fail("unavailable", result); return }
        if enabled {
          let permission = AVCaptureDevice.authorizationStatus(for: .video)
          if permission == .notDetermined {
            guard !pendingPermission else { fail("unavailable", result); return }
            pendingPermission = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
              DispatchQueue.main.async {
                guard let self = self else { result(FlutterError(code: "inactive", message: "Session ended", details: nil)); return }
                self.pendingPermission = false
                // Never replay a write after the permission sheet changes focus.
                self.fail(allowed ? "inactive" : "permissionDenied", result)
              }
            }
            return
          }
          guard permission == .authorized else { fail("permissionDenied", result); return }
        }
        do {
          try device.lockForConfiguration()
          defer { device.unlockForConfiguration() }
          device.torchMode = enabled ? .on : .off
          ownsTorch = enabled
        } catch { fail("unavailable", result); return }
      case "brightness":
        if value == nil || value is NSNull { reset(control) }
        else {
          guard let level = value as? Double, level.isFinite, (0...1).contains(level), let screen = screen else { fail("invalid", result); return }
          if previousBrightness == nil { previousBrightness = screen.brightness; controlledScreen = screen }
          screen.brightness = CGFloat(level)
        }
      case "keepAwake":
        guard let enabled = value as? Bool else { fail("invalid", result); return }
        if enabled {
          if previousAwake == nil { previousAwake = UIApplication.shared.isIdleTimerDisabled }
          UIApplication.shared.isIdleTimerDisabled = true
        } else { reset(control) }
      case "haptics":
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { fail("unavailable", result); return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      default: fail("invalid", result); return
      }
      result(nil); changed()
    default: result(FlutterMethodNotImplemented)
    }
  }
  private func snapshot() -> [String: Any] {
    var values: [String: Any] = [:]
    let device = UIDevice.current
    if grants.contains("battery") {
      if device.batteryLevel >= 0 { values["batteryLevel"] = Int((device.batteryLevel * 100).rounded()) }
      switch device.batteryState {
      case .charging: values["charging"] = "Charging"
      case .full: values["charging"] = "Full"
      case .unplugged: values["charging"] = "Not charging"
      default: values["charging"] = "Unknown"
      }
    }
    if grants.contains("device") { values["model"] = device.model; values["osVersion"] = "\(device.systemName) \(device.systemVersion)" }
    if grants.contains("locale") {
      values["language"] = Locale.preferredLanguages.first ?? "Unknown"
      values["region"] = Locale.current.regionCode ?? "Unknown"
      values["timeZone"] = TimeZone.current.identifier
    }
    if grants.contains("connection") { values["connection"] = connection ?? "Unknown" }
    if grants.contains("flashlight") { values["flashlight"] = torch?.isTorchActive ?? false }
    if grants.contains("brightness"), let brightness = screen?.brightness { values["brightness"] = Double(brightness) }
    if grants.contains("keepAwake") { values["keepAwake"] = UIApplication.shared.isIdleTimerDisabled }
    var availability = Dictionary(uniqueKeysWithValues: capabilities.map { ($0, "available") })
    if torch?.hasTorch != true || torch?.isTorchAvailable != true { availability["flashlight"] = "unavailable" }
    if !CHHapticEngine.capabilitiesForHardware().supportsHaptics { availability["haptics"] = "unavailable" }
    return ["values": values, "availability": availability]
  }
  private func startMonitoring() {
    if grants.contains("battery") {
      previousBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
      UIDevice.current.isBatteryMonitoringEnabled = true
      for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
        batteryObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.changed() })
      }
    }
    if grants.contains("connection") {
      let monitor = NWPathMonitor(); self.monitor = monitor
      monitor.pathUpdateHandler = { [weak self, weak monitor] path in
        DispatchQueue.main.async {
          guard let self = self, let monitor = monitor, self.monitor === monitor, self.grants.contains("connection") else { return }
          self.connection = path.status != .satisfied ? "None" : path.usesInterfaceType(.wifi) ? "Wi-Fi" : path.usesInterfaceType(.cellular) ? "Cellular" : "Other"
          self.changed()
        }
      }
      monitor.start(queue: DispatchQueue(label: "appnest.device.connection"))
    }
    if grants.contains("flashlight") {
      torchObservation = torch?.observe(\.isTorchActive, options: [.new]) { [weak self] _, _ in self?.changed() }
    }
  }
  private func stopMonitoring() {
    monitor?.cancel(); monitor = nil; connection = nil
    batteryObservers.forEach { NotificationCenter.default.removeObserver($0) }; batteryObservers.removeAll()
    if let previous = previousBatteryMonitoring { UIDevice.current.isBatteryMonitoringEnabled = previous }
    previousBatteryMonitoring = nil
    torchObservation = nil
  }
  private func reset(_ control: String) {
    if control == "flashlight", ownsTorch {
      if let device = torch {
        do { try device.lockForConfiguration(); device.torchMode = .off; device.unlockForConfiguration() } catch { }
      }
      ownsTorch = false
    }
    if control == "brightness", let previous = previousBrightness {
      controlledScreen?.brightness = previous; previousBrightness = nil; controlledScreen = nil
    }
    if control == "keepAwake", let previous = previousAwake {
      UIApplication.shared.isIdleTimerDisabled = previous; previousAwake = nil
    }
  }
  private func release() {
    stopMonitoring()
    ["flashlight", "brightness", "keepAwake"].forEach { reset($0) }
    session = nil; grants.removeAll()
  }
}
