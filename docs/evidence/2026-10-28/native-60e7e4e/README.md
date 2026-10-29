# Native source checkpoint: 60e7e4e4

Built from committed source `60e7e4e45f57a511d9373e60f06f4e308551995f` with 314 tracked mobile blobs. Input SHA-256: `dc7654dd34e46a7f2f47a819de529fb6baa3a59b5190b077540f934c3aba958b`. Compiled-source SHA-256: `5d9c16e6516014dd82b42e03043fdb43598f683a9b67140ea30fc24ed97fa926`. Native configuration, dependencies and all 11 custom native-module files match the prior 0acf9ead preparation; only the recorded Expo CNG package-script transform differs.

| Artifact | Build time | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| android | 34.19s | 263,603,780 | `ee3f23a822e17adb0a135857beed7a17bb972ba687e6908ba482981b8506869b` |
| ios | 22.15s | 23,554,503 | `a269c998d60d60a3ca3ee8609cf5992f7dfb5db97a50c47ae51c9cf17eba61a1` |
| android-release | 42.25s | 116,536,234 | `4a1249c2748966348e1a3c8fbf902f9a92650ff6d6a0c6b62cd44c0bf3340070` |

Android Debug contains no embedded JavaScript and requires Metro; its separate exact-source export passed. Android local Release embeds a self-contained Hermes JavaScript bundle and uses the unchanged generated development debug signing key. Its manifest is nondebuggable, but it is not production/store-signed. iOS Simulator Release embeds Hermes bytecode and is unsigned.

Typecheck, lint and all-platform exports passed using actual installed dependencies. The web/iOS/Android exports and both embedded release bundles contain all 16 requested source markers and 16 route keys, including published customization, original-record retry controls, both superseded-read markers, the guarded-read queue capacity message, and the superseded-reminder-read message. This proves source inclusion, not semantic runtime behavior. Both release embedded-bundle hashes differ from 0acf9ead.

Packaged native registrations include the custom device module and ImagePicker. The Android release inspection uses its actual R8 mapping and DEX class-definition table. The unchanged public development certificate SHA-256 is `fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c`. Blocked storage/audio permissions are absent; CAMERA remains for the explicit flashlight capability. iOS usage strings match the existing camera/photo configuration and contain no microphone description.

The eight original sandbox-failure receipt/log files from the historical 0acf9ead checkpoint remain preserved and hash-checked through the cumulative preservation manifest. This checkpoint uses existing Gradle/Xcode cache access from its first native build attempt.

All 2,873 prior immutable files, including 0acf9ead, 48afbd65, 916b8773, a1e34c7f and 10fed99 artifacts and older failures, remain intact. No device/simulator was booted, installed or launched. Native Appwrite sign-in, photo selection, torch behavior, hardware permissions, UI and accessibility remain unverified. No EAS, production signing or deployment is represented by this source checkpoint. The migration remains in progress.
