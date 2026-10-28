# Mobile capabilities

[Documentation index](README.md) · [Customization](CUSTOMIZATION.md) · [iPhone evidence](IPHONE_AI_CHECK.md) · [Development workflow](DEVELOPMENT.md)

AppNest mini-apps can display local device information and offer bounded phone
controls on Android and iOS. Add them through **Customize → Mobile features**,
the component editor, or the AI builder. **Phone Toolkit** is an explicit starter
with separate My phone and Controls tabs. Selecting its idea chip requests AI
creation; selecting its template uses the deterministic definition.

## Supported features

| Component | Supported values or behavior |
| --- | --- |
| Device information | Battery percentage, charging state, model/family, OS version, active connection type, language, region, time zone |
| Flashlight | Explicit on/off; unavailable hardware and camera conflicts are reported |
| Brightness | Foreground brightness slider and Restore brightness |
| Keep screen awake | Explicit toggle while the mini-app is active |
| Haptic feedback | One feedback pulse on a button tap, when supported and enabled by the OS |

Connection type is not an internet reachability test. iOS reports the public
device family rather than a private hardware identifier. No serial number,
advertising identifier, user-assigned device name, Wi-Fi SSID, or address is read.
Location, contacts, native calendar integration, phone notifications, background
rules, Wi-Fi/Bluetooth switching, and runtime device chat are not supported.

## Consent and lifetime

Publication lists the requested device capabilities but grants no device access.
Each signed-in person enables capabilities through **Mini-app menu → Device
access** or the same button on a component. Information access is grouped into
battery/charging, device/OS, connection, and locale. Each control has its own grant.
All grants start off and are stored locally, scoped by backend, account, and app.
New capability groups stay off. **Reset device access** clears local grants and
can recover a corrupt consent preference. Preference errors are displayed rather
than reported as saved changes.

The native camera permission is requested only when the flashlight is explicitly
turned on. After a permission prompt, the person may need to tap the control
again: commands are never automatically replayed after a focus interruption.
Denied permission offers AppNest system settings; busy or unavailable hardware
reports failure. Haptics respect hardware and OS settings.

Queries refresh on entry, foreground return, and Refresh; battery and connection
changes are observed while enabled and visible. Values exist only in memory and
never enter Serverpod, app records, AI messages, telemetry, or preferences.
Switching mini-apps, closing the last device component, leaving for customization,
backgrounding, or revoking a capability releases the relevant native resources.
A session token prevents late cleanup from affecting another mini-app.

AppNest turns off a flashlight it enabled, restores prior brightness, and releases
its keep-awake setting. Native lifecycle handlers complement Flutter cleanup.
iOS brightness restoration is best-effort if the process terminates abruptly;
Apple documents that a changed brightness can remain until device lock. This
feature is not a system-wide persistent settings service.

Web and desktop display **Available in the Android or iOS app** and make no native
calls. Builder previews use isolated, labeled synthetic readings and simulated
controls. Preview grants cannot enable a live phone feature.

## Implementation contract

AppSpec adds collection-free `deviceInfo` and `deviceControl` views with
`views.deviceInfo.v1` and `views.deviceControl.v1`. Configured views also require
`views.configured.v1` and navigation. Device information options contain a nonempty
`fields` list from `batteryLevel`, `charging`, `model`, `osVersion`, `connection`,
`language`, `region`, and `timeZone`. Control options contain exactly one `control`
from `flashlight`, `brightness`, `keepAwake`, and `haptics`. These views cannot bind
records, queries, or record actions. No automatic on-load control value is allowed.

`DeviceCapabilitiesAdapter` is the renderer's typed local interface. The Flutter
host owns consent, command serialization, state filtering, and lifecycle guards.
Fixed Kotlin and Swift bridges implement `appnest/device` methods and change
notifications on `appnest/device/events`. Definitions cannot name channel methods
or execute native code. Serverpod validates/publishes definitions using existing
authenticated services. There are no new device endpoints, tables, or migrations.
Existing AppSpec hashes remain unchanged unless their definition is edited.

This local-device boundary is separate from record action receipts and legacy
record rendering. The [architecture review](ARCHITECTURE_REVIEW.md) records open
ambiguous business-Save and legacy access-error UI findings; device session
cleanup does not resolve them.

## Initial verification — 2026-09-24

The results below describe the environment and source used on that date. They
are not a current inventory of installed Xcode components, connected devices,
or running services. The subsequent dated check follows the initial results.

- `scripts/verify.sh` passed: analysis, formatting, **539 tests** (80 spec,
  171 renderer, 168 Flutter app, 120 server), and isolated two-process PostgreSQL
  reminder restart recovery. The run recorded its temporary log at
  `/tmp/appnest-mobile-verify.log`; that file is not a repository artifact.
- Tests cover bounded schemas, semantic edits, reachable generation, publication
  without device data or grants, local consent isolation, revocation, corrupt
  preferences/reset, interrupted commands, permission errors, lifecycle cleanup,
  unsupported platforms, synthetic preview isolation, manual authoring, and large
  text layouts.
- Web release compilation passed with native capabilities unavailable.
- Android release compilation passed. Physical Android behavior remains unverified:
  no Android device was connected.
- The Swift bridge, AppDelegate registration, and SceneDelegate passed direct
  `swiftc -typecheck` with the installed iPhoneOS SDK and Flutter framework.
- Full iOS build/install is blocked: Xcode reports **iOS 26.5 is not installed** in
  Settings → Components. The paired Frank iPhone17 is visible but ineligible for
  this build. Swift type-checking does not establish app linking or phone behavior.
- No updated development server was started/restarted; Serverpod/Dart MCP tools
  were not available. No live AI call, production deployment, commit, or push was
  performed for this change.

Later on 2026-09-24, after the Xcode setup was completed, the signed iOS release
build and signature verification passed. The backend was restarted with explicit
authorization, and Phone Toolkit AI creation reached a validated browser preview
on its first attempt after the provider-contract fix. Installation of the later
Resume build frontend update could not proceed because the iPhone was unavailable.
Physical-device generation and controls remain unverified. See the
[subsequent iPhone and browser investigation](IPHONE_AI_CHECK.md) for the later
evidence and its limits.

Synthetic screenshots use test data, not physical-phone readings:

| View | Mobile | Desktop |
| --- | --- | --- |
| Information | [Capture](evidence/mobile/device-phonePage-390.png) | [Capture](evidence/mobile/device-phonePage-1440.png) |
| Controls | [Capture](evidence/mobile/device-controlsPage-390.png) | [Capture](evidence/mobile/device-controlsPage-1440.png) |
| Access off | [Capture](evidence/mobile/device-accessOff-390.png) | [Capture](evidence/mobile/device-accessOff-1440.png) |
| Unsupported platform | [Capture](evidence/mobile/device-unavailable-390.png) | [Capture](evidence/mobile/device-unavailable-1440.png) |
