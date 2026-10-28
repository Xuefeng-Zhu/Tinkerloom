import ExpoModulesCore
import UIKit
import AVFoundation
import CoreHaptics

public class TinkerloomDeviceModule: Module {
  private var lease: String?
  private var ownsTorch = false
  private var previousBrightness: CGFloat?
  private weak var controlledScreen: UIScreen?
  private var previousAwake: Bool?
  private var inactiveObserver: NSObjectProtocol?
  private var torch: AVCaptureDevice? {
    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
  }
  private var screen: UIScreen? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first(where: { $0.activationState == .foregroundActive })?.screen
  }
  private func failure(_ code: String) -> Exception {
    Exception(name: "DeviceRequest", description: "The device request could not be completed.", code: code)
  }
  private func claim(_ token: String) throws {
    guard !token.isEmpty && token.count <= 128 else { throw failure("invalid") }
    guard UIApplication.shared.applicationState == .active else { throw failure("inactive") }
    if lease != token { releaseAll(); lease = token }
  }
  public func definition() -> ModuleDefinition {
    Name("TinkerloomDevice")
    OnCreate {
      self.inactiveObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.releaseAll() }
    }
    OnAppEntersBackground { self.releaseAll() }
    OnDestroy {
      if let observer = self.inactiveObserver { NotificationCenter.default.removeObserver(observer) }
      self.releaseAll()
    }
    AsyncFunction("availability") { () -> [String: Bool] in
      ["flashlight": self.torch?.hasTorch == true && self.torch?.isTorchAvailable == true,
       "brightness": self.screen != nil, "keepAwake": true,
       "haptics": CHHapticEngine.capabilitiesForHardware().supportsHaptics]
    }.runOnQueue(.main)
    AsyncFunction("setTorch") { (enabled: Bool, token: String) in
      try self.claim(token)
      guard let torch = self.torch, torch.hasTorch, torch.isTorchAvailable else { throw self.failure("unavailable") }
      if enabled && AVCaptureDevice.authorizationStatus(for: .video) != .authorized { throw self.failure("permission_denied") }
      if !enabled && !self.ownsTorch { return }
      do {
        try torch.lockForConfiguration()
        defer { torch.unlockForConfiguration() }
        if enabled { try torch.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) }
        else { torch.torchMode = .off }
        self.ownsTorch = enabled
      } catch { throw self.failure("unavailable") }
    }.runOnQueue(.main)
    AsyncFunction("setBrightness") { (value: Double?, token: String) in
      try self.claim(token)
      guard let value = value else { self.reset("brightness"); return }
      guard value.isFinite && (0...1).contains(value), let screen = self.screen else { throw self.failure("invalid") }
      if self.previousBrightness == nil { self.previousBrightness = screen.brightness; self.controlledScreen = screen }
      screen.brightness = CGFloat(value)
    }.runOnQueue(.main)
    AsyncFunction("setKeepAwake") { (enabled: Bool, token: String) in
      try self.claim(token)
      if enabled {
        if self.previousAwake == nil { self.previousAwake = UIApplication.shared.isIdleTimerDisabled }
        UIApplication.shared.isIdleTimerDisabled = true
      } else { self.reset("keepAwake") }
    }.runOnQueue(.main)
    AsyncFunction("release") { (control: String, token: String) in
      guard ["flashlight", "brightness", "keepAwake", "haptics"].contains(control) else { throw self.failure("invalid") }
      if self.lease == token && !self.reset(control) { throw self.failure("unavailable") }
    }.runOnQueue(.main)
  }
  @discardableResult private func reset(_ control: String) -> Bool {
    var released = true
    if control == "flashlight" && ownsTorch {
      guard let torch = torch else { return false }
      do { try torch.lockForConfiguration(); torch.torchMode = .off; torch.unlockForConfiguration(); ownsTorch = false }
      catch { released = false /* Keep ownership so a later lifecycle release can retry. */ }
    }
    if control == "brightness", let original = previousBrightness {
      controlledScreen?.brightness = original; previousBrightness = nil; controlledScreen = nil
    }
    if control == "keepAwake", let original = previousAwake {
      UIApplication.shared.isIdleTimerDisabled = original; previousAwake = nil
    }
    return released
  }
  private func releaseAll() {
    ["flashlight", "brightness", "keepAwake"].forEach { _ = reset($0) }
    if !ownsTorch { lease = nil }
  }
}
