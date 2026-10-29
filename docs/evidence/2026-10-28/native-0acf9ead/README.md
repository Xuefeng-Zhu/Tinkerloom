# Native source checkpoint: 0acf9ead

Built from committed source `0acf9eadeed00b3cd966c57465a36ce9ffc823fb` with 311 tracked mobile blobs. Input SHA-256: `2dd7ac97e671ff16729ed207f27186de64cb0d70d67b6d5de424411df87c10c8`. Compiled-source SHA-256: `639c8b8b8556154877a297135061bf85beeb302f437240884982fdb6b6bb6623`. Native configuration, dependencies and all 11 custom native-module files match the prior 48afbd65 preparation; only the recorded Expo CNG package-script transform differs.

| Artifact | Build time | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| android | 38.19s | 263,603,780 | `ee3f23a822e17adb0a135857beed7a17bb972ba687e6908ba482981b8506869b` |
| ios | 36.21s | 23,553,216 | `9b284ea71dd2d0a7b39052fcbd8346325a28ef8e86a699636f90ac0d782cfb04` |
| android-release | 46.2s | 116,532,910 | `d07595e4aaed2e1391ff6bc77bb3cb45481884df4a41dec44b6098c7ab0c6fd1` |

Android Debug contains no embedded JavaScript and requires Metro; its separate exact-source export passed. Android local Release embeds Hermes bytecode, runs without Metro, and uses the unchanged generated development debug signing key. Its manifest is nondebuggable, but it is not production/store-signed. iOS Simulator Release embeds Hermes bytecode and is unsigned.

Typecheck, lint and all-platform exports passed using actual installed dependencies. The web/iOS/Android exports and both embedded release bundles contain all 15 requested source markers and 16 route keys, including published customization, original-record retry controls, both superseded-read markers, and the guarded-read queue capacity message. This proves source inclusion, not semantic runtime behavior. Both release embedded-bundle hashes differ from 48afbd65.

Packaged native registrations include the custom device module and ImagePicker. The Android release inspection uses its actual R8 mapping and DEX class-definition table. The unchanged public development certificate SHA-256 is `fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c`. Blocked storage/audio permissions are absent; CAMERA remains for the explicit flashlight capability. iOS usage strings match the existing camera/photo configuration and contain no microphone description.

Initial native attempts without standard cache access failed before compilation. Their original eight receipt/log files remain preserved under `preserved-sandbox-attempt/` with SHA-256 mapping in `sandbox-attempt-preservation.json`; the same-source builds then succeeded with existing Gradle/Xcode cache access.

All 2,403 prior immutable files, including 48afbd65, 916b8773, a1e34c7f and 10fed99 artifacts and older failures, remain intact. No device/simulator was booted, installed or launched. Native Appwrite sign-in, photo selection, torch behavior, hardware permissions, UI and accessibility remain unverified. No EAS, production signing or deployment is represented by this source checkpoint. The migration remains in progress.
