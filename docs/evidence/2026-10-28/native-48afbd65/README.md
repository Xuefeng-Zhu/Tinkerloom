# Native source checkpoint: 48afbd65

Built from committed source `48afbd65b3db577442aa8c7fc82a69cfd21dc747` with 308 tracked mobile blobs. Input SHA-256: `2855a0c9af00784792510de4de195e361760c945ac74bc8de4b169f7895254f4`. Compiled-source SHA-256: `3ddf2baa013e4962805c492152d0abcba66b65048202042ad7491cb2c4f68259`. Native configuration, dependencies and all 11 custom native-module files match the prior 916b8773 preparation; only the recorded Expo CNG package-script transform differs.

| Artifact | Build time | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| android | 36.17s | 263,603,780 | `ee3f23a822e17adb0a135857beed7a17bb972ba687e6908ba482981b8506869b` |
| ios | 22.16s | 23,550,799 | `8f1dcb64e43f3c557dc0958a8e9d1709826b9bda3492f337d25ac38b6b082cc7` |
| android-release | 42.21s | 116,529,370 | `7101a9ec78a35c05f0feb790852578f133256d28f4b597d96a26b1082e0dedae` |

Android Debug contains no embedded JavaScript and requires Metro; its separate exact-source export passed. Android local Release embeds Hermes bytecode, runs without Metro, and uses the unchanged generated development debug signing key. Its manifest is nondebuggable, but it is not production/store-signed. iOS Simulator Release embeds Hermes bytecode and is unsigned.

Typecheck, lint and all-platform exports passed using actual installed dependencies. The web/iOS/Android exports and both embedded release bundles contain all 14 requested source markers and 16 route keys, including published customization, original-record retry controls, and the superseded-full-read and superseded-workspace-read markers. This proves source inclusion, not semantic runtime behavior. Both release embedded-bundle hashes differ from 916b8773.

Packaged native registrations include the custom device module and ImagePicker. The Android release inspection uses its actual R8 mapping and DEX class-definition table. The unchanged public development certificate SHA-256 is `fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c`. Blocked storage/audio permissions are absent; CAMERA remains for the explicit flashlight capability. iOS usage strings match the existing camera/photo configuration and contain no microphone description.

All 1,946 prior immutable files, including 916b8773, a1e34c7f and 10fed99 artifacts and older failures, remain intact. No device/simulator was booted, installed or launched. Native Appwrite sign-in, photo selection, torch behavior, hardware permissions, UI and accessibility remain unverified. No EAS, production signing or deployment is represented by this source checkpoint. The migration remains in progress.
