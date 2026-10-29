# Native source checkpoint: a1e34c7f

Built from committed source `a1e34c7f1d26bd14a91b92dc4dd7d9d4d1a9551e` with 301 tracked mobile blobs. Input SHA-256: `aee5aa804841946d7705b0783c772ab72badc10375afc7baa64c5abca886d786`. Compiled-source SHA-256: `8f90b7b84d124e986db67c435336cbbc63c70b294053efc9828d58981b9eedb0`. Native configuration, dependencies and all 11 custom native-module files match the prior 10fed99 preparation; only the recorded Expo CNG package-script transform differs.

| Artifact | Build time | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| android | 32.16s | 263,603,780 | `ee3f23a822e17adb0a135857beed7a17bb972ba687e6908ba482981b8506869b` |
| ios | 22.18s | 23,549,319 | `b995566d824ca1ecb85ef2dc69806cb7071275e73236351984729c8bee4e456e` |
| android-release | 48.23s | 116,524,506 | `e205ad93487099829c0959b5d3d82334b317d6372969f2832ac0b756364f9633` |

Android Debug contains no embedded JavaScript and requires Metro; its separate exact-source export passed. Android local Release embeds Hermes bytecode, runs without Metro, and uses the unchanged generated development debug signing key. Its manifest is nondebuggable, but it is not production/store-signed. iOS Simulator Release embeds Hermes bytecode and is unsigned.

Typecheck, lint and all-platform exports passed using actual installed dependencies. The web/iOS/Android exports and both embedded release bundles contain all 12 requested source markers and 16 route keys, including published customization and original-record retry controls. This proves source inclusion, not semantic runtime behavior. Both release embedded-bundle hashes differ from 10fed99.

Packaged native registrations include the custom device module and ImagePicker. The Android release inspection uses its actual R8 mapping and DEX class-definition table. The unchanged public development certificate SHA-256 is `fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c`. Blocked storage/audio permissions are absent; CAMERA remains for the explicit flashlight capability. iOS usage strings match the existing camera/photo configuration and contain no microphone description.

All 1,038 prior immutable files, including 10fed99 artifacts and older failures, remain intact. No device/simulator was booted, installed or launched. Native Appwrite sign-in, photo selection, torch behavior, hardware permissions, UI and accessibility remain unverified. No EAS, production signing or deployment is represented by this source checkpoint. The migration remains in progress.
