# Native module compilation — October 28, 2026

Both full native compilations passed against the fixed source snapshot in
`/private/tmp/tinkerloom-native-module-4g365zp6/app` copied from the persistent
Tinkerloom client. This verifies the local module and dependencies in that
snapshot, not later full-host wiring or hardware behavior.

Input snapshot: 169 source/config/package files, SHA-256
`cf37a644b4726d5df0fff3dac0df48875be49781c768ed2962ce1813d1f249f5`.
Expo CNG modified only the copied package scripts; compiled source manifest:
`2bc5f61585eeaee308da419a2de9b68180f4f24ac12bce5dd815bb8b5f9864d8`.
All native module source hashes remained unchanged. No Swift/Kotlin fixes or
persistent source edits were needed.

The first copy incorrectly omitted nested module native folders. That was caught
by autolinking inspection, its Android build was stopped and its logs/receipt
preserved with an `interrupted-native-source-correction` suffix. The corrected
snapshot added and verified all five native module source/config files before
the accepted builds. Superseded prebuild/pod logs are preserved separately.
The accepted autolinking resolver outputs include TinkerloomDevice on both
platforms; its actual classes are present in the finished binaries.

## Commands and outcomes

- Expo CNG `npx --no-install expo prebuild --platform all --no-install --skip-dependency-update react,react-native`: exit code 0, 6.88s.
- Generated iOS `pod install`: exit code 0, 80.71s, including TinkerloomDevice 0.1.0.
- `xcodebuild -workspace ios/Tinkerloom.xcworkspace -scheme Tinkerloom -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tinkerloom-native-module-4g365zp6/ios-derived-data CODE_SIGNING_ALLOWED=NO build`: exit code 0, 1685.98s, BUILD SUCCEEDED.
- Android `./gradlew :app:assembleDebug --no-daemon --console=plain`, using existing Android SDK and Java 25: exit code 0, 1756.77s, BUILD SUCCESSFUL.

Toolchain: Expo 58.0.20, React Native 0.88.0, Node 24.14.1, Xcode 27.1(27A9275),
iOSSimulator SDK 27.1, CocoaPods 1.17.0, Gradle 9.4.1, Android compile SDK 37,
Build Tools 37.0.0, Java 25.0.2. No SDK install, EAS, paid service, new signing
identity or account credential was used.

## Inspected artifacts

Artifacts and sanitized receipts are under `artifacts/` beside this report.

| Artifact                                     |     Bytes | SHA-256                                                            |
| -------------------------------------------- | --------: | ------------------------------------------------------------------ |
| Tinkerloom-ios-simulator-module-2bc5f615.zip |  23010191 | `f3598617d49d0435a6c884b1288a398be17d7fc4c80cce519ddb176499d0e6c6` |
| Tinkerloom-android-debug-module-2bc5f615.apk | 263114861 | `99b3c18a484ae9dc14eeb559106832e45aa47ab818fdd177d69d2ed5ef2c9bf5` |

iOS: universal arm64/x86_64, bundle ID com.tinkerloom.app, minimum OS 16.4,
signing disabled, embedded Hermes bytecode 99. The generated provider registers
TinkerloomDeviceModule and linked symbols contain the custom Swift class.
The source emits one nonfatal ImplicitStrongCapture warning at Swift line 33;
no warning-suppression or source change was applied.

Android: arm64-v8a/armeabi-v7a/x86/x86_64 libraries, package com.tinkerloom.app,
minimum SDK 24/target 36/compile 37. Custom Kotlin class descriptor is present in
DEX. apksigner verification exits 0; this is the generated development signing
configuration, not production signing. The debug APK has no embedded JavaScript
bundle and requires a development Metro server to run application code.

## Boundaries and preserved baseline

The matching ignored .env.local contained only verified EXPO_PUBLIC keys; values
were never printed and are excluded from source receipts. The earlier baseline
source/logs/receipts/artifacts remain intact; only an APFS clone of derived data
was reused. The previous APK and iOS executable still match their recorded
648b68... and 58203... hashes; full hashes are in toolchain-and-preservation.json.
Raw logs remain local in logs/ and should not be committed because Xcode emits
extensive environment/build settings.

The same pre-existing CoreSimulator service version mismatch appeared; generic
compilation succeeded. No simulator/device was booted, no artifact was installed
or launched, no OS permission was requested, and no system service was restarted.
This does not verify native authentication/CRUD, new full-host wiring, device
consent/restoration, accessibility or hardware behavior. Those need separate
execution against the final integrated client and backend.
