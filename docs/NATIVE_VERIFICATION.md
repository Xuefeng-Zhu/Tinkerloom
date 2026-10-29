# Current native verification

The latest source-specific checkpoint is `48afbd65b3db577442aa8c7fc82a69cfd21dc747`: all three native builds and an independent artifact audit passed. The [checkpoint and artifact summary](evidence/2026-10-28/native-48afbd65/README.md) bind 308 tracked mobile files, current native dependencies and the unchanged custom module to the actual packages. Both embedded releases contain the current published editor, record recovery and app/workbench read recovery code. The FullAppScreen source hash includes the runtime-preparation guard.

Android local Release embeds JavaScript and uses development debug signing. iOS Simulator Release embeds JavaScript and is unsigned. Android Debug requires Metro. [Stable local artifacts](evidence/2026-10-28/native-48afbd65/stable-local-artifacts.json) records the usable ignored binaries and hashes. No installation, native sign-in, native UI, device/hardware or production signing is proven. Separate mounted web recovery checks use synthetic network/storage ports and do not establish native runtime behavior.

Earlier audited checkpoints [916b8773](evidence/2026-10-28/native-916b8773/README.md) and [a1e34c7f](evidence/2026-10-28/native-a1e34c7f/README.md) retain their original source identities and limits, as do the historical reports below.

# Native compilation evidence — October 28, 2026

Both native compilation commands completed successfully against an isolated
snapshot of `apps/mobile`. This is a native build baseline, not acceptance of
the completed migration. The snapshot predates the later Expo Crypto and
Clipboard additions and concurrent sharing/publication work. Repeat native
generation and compilation against the final source and dependencies before
claiming final native coverage.

## Source and toolchain

- Source staging directory: `/private/tmp/tinkerloom-full-migration-pOaTwL/apps/mobile`.
- Isolated native build directory: `/private/tmp/tinkerloom-native-build-69mSqY/app`.
- Source/config/package-file snapshot SHA-256: `e5a497eb5c3aace1b330d472735d362a2a65ed82b548a8e7fa578fe6427cab5f`.
- Expo 58.0.20, React Native 0.88.0, Node 24.14.1.
- Xcode 27.1 (27A9275), iOS Simulator SDK 27.1, CocoaPods 1.17.0.
- Android compile SDK 37, Build Tools 37.0.0, Gradle 9.4.1, Java 25.0.2.
- Application identifier on both platforms: `com.tinkerloom.app`.

The ignored `.env.local` was copied from the persistent client after verifying
that it contained only public `EXPO_PUBLIC_APPWRITE_*` configuration. Values
were not printed. The snapshot checksum excludes that ignored configuration.
Native generation and package-script changes were confined to the isolated copy.

Android SDK Platform 37.0 and Build Tools 37.0.0 were downloaded with the
official installed Android tools. The current platform package name is
`platforms/android-37.0`; the older `platforms;android-37` request did not resolve
the platform. Input was disabled during installation, and the existing accepted
license files were unchanged. No new terms were accepted.

## Build commands and outcomes

The native projects were generated using the installed official Expo template:

```sh
npx expo prebuild --platform all --no-install --skip-dependency-update react,react-native
```

`pod install` from the generated `ios/` directory completed with exit code 0.
The iOS simulator app was then compiled from the isolated app directory:

```sh
xcodebuild \
  -workspace ios/Tinkerloom.xcworkspace \
  -scheme Tinkerloom \
  -configuration Release \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/tinkerloom-native-build-69mSqY/ios-derived-data \
  CODE_SIGNING_ALLOWED=NO build
```

Result: exit code **0**, `BUILD SUCCEEDED`, elapsed **1,409.52 seconds**.
The app contains a universal Mach-O executable for **arm64 and x86_64** and
embedded **Hermes bytecode version 99**. Its minimum iOS version is **16.4**.
Code signing was disabled. This is a simulator build; it is not an iPhone
distribution build or evidence of installation or execution.

From the generated Android directory, with `ANDROID_HOME` pointing at the
existing Android SDK:

```sh
./gradlew :app:assembleDebug --no-daemon --console=plain
```

Result: exit code **0**, `BUILD SUCCESSFUL`, elapsed **1,650.25 seconds**.
The APK contains native libraries for **arm64-v8a, armeabi-v7a, x86, and x86_64**.
Inspection with `aapt2` confirmed application ID `com.tinkerloom.app`, compile
SDK **37**, minimum SDK **24**, and target SDK **36**. `apksigner verify --verbose`
completed with exit code 0 and verified its APK v2 signature. It uses the
generated project's development signing configuration, not a production
signing identity. The **debug APK has no embedded JavaScript bundle** and needs
the development Metro server to run the application code.

Neither artifact was installed or launched. No simulator/device was booted,
no EAS operation was used, and no paid hardware service was used.

## Preserved artifacts and hashes

Artifacts and sanitized JSON receipts are retained in the ignored directory
`/Users/frank/mygit/Tinkerloom/output/native/2026-10-28/`:

| Artifact                                | Size (bytes) | SHA-256                                                            |
| --------------------------------------- | -----------: | ------------------------------------------------------------------ |
| `Tinkerloom-ios-simulator-e5a497eb.zip` |   21,874,588 | `24fd319360c273c6812186e6a2a5a1883f229f26bf1a6c12d3d2fb1d223ab90d` |
| `Tinkerloom-android-debug-e5a497eb.apk` |  236,873,246 | `648b68e3c126745c72237e76e7fa43c311c0b0e2f2fc477f59132cdc9c6e4bdf` |

The iOS zip contains the compiled `Tinkerloom.app`. The simulator executable
SHA-256 is `58203b058dc923e79df6f37e25c3b61979f9c3a86cda619e7bde92fe2fafed99`;
the embedded Hermes bundle SHA-256 is
`6ba04f627ae41fdf5fe132746e385f025483a6a7db1ce1a719dbfdc6c82a57ad`.

The receipts `ios-receipt-e5a497eb.json` and
`android-receipt-e5a497eb.json` contain the executed commands, durations,
source snapshot, architecture metadata, and artifact hashes. Raw build logs
remain local under `/private/tmp/tinkerloom-native-build-69mSqY/logs/` and are
not committed because Xcode logs contain extensive environment/build settings.

## Runtime acceptance still outstanding

The build log reported CoreSimulator service **1171.7.0**, older than Xcode's
build **1174.9.2**, and disabled simulator device support. Generic simulator
compilation succeeded despite that runtime problem. No service restart was
performed. The local Android SDK has no emulator package or AVD configured.

Compilation does not establish native Appwrite authentication, live CRUD,
sharing, reminders, device capabilities, accessibility, or physical-device
behavior. Those layers require separate execution against the final client
and backend.

## Custom native module and dependency checkpoint

The later [module compilation report](evidence/2026-10-28/native-module/README.md)
and [iOS](evidence/2026-10-28/native-module/ios-receipt.json) /
[Android](evidence/2026-10-28/native-module/android-receipt.json) receipts record
successful full local builds of the custom TinkerloomDevice module and current
native dependencies. Both native classes were verified inside the resulting
binaries; no Swift/Kotlin source fixes were needed. The iOS observer has one
nonfatal capture-ownership warning. This checkpoint predates later full-host
wiring and does not establish final-source or device acceptance.

The fixed input snapshot contains **169 files** and has SHA-256
`cf37a644b4726d5df0fff3dac0df48875be49781c768ed2962ce1813d1f249f5`.
Expo CNG changed only copied package scripts, giving compiled-source SHA-256
`2bc5f61585eeaee308da419a2de9b68180f4f24ac12bce5dd815bb8b5f9864d8`.
All native module source hashes remained unchanged. Matching ignored public
configuration was verified before copying; no values were printed.

The same Xcode 27.1/Simulator SDK 27.1, Gradle 9.4.1/Android SDK 37/Java 25 toolchain
was used. iOS Generic Simulator Release with signing disabled passed in
**1,685.98s**; Android assembleDebug passed in **1,756.77s**. iOS contains arm64
and x86_64 plus embedded Hermes bytecode 99. Android contains all four ABIs,
minimum SDK 24/target 36/compile 37 and passes APK signature verification; its debug
APK has no embedded JavaScript and requires Metro. Exact toolchain and baseline
preservation hashes are in the [third receipt](evidence/2026-10-28/native-module/toolchain-and-preservation.json).

The zip/APK are preserved under ignored `output/native/module/`; exact names,
sizes and hashes are in the receipts. Earlier baseline artifacts and reports
remain unchanged. No simulator/device was booted, no app was installed or
launched, no OS permission was requested, and no EAS/paid service or new signing
identity was used. The existing CoreSimulator version mismatch remains a
runtime limitation despite successful generic compilation.
