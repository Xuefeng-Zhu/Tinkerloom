# Native source checkpoint: 916b8773

Built from committed source `916b877314e5e06300c6ac0811f2622d58561328` with 303 tracked mobile blobs. Input SHA-256: `892216f357dc23e7a609eea9423f77f128205a0c40269090989a3f4bf4838831`. Compiled-source SHA-256: `6474698e61d14e0291a2325d59281d2c78208e3376b3a4fa7f386c1c747c2063`. Native configuration, dependencies and all 11 custom native-module files match the prior a1e34c7f preparation; only the recorded Expo CNG package-script transform differs.

| Artifact | Build time | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| android | 34.27s | 263,603,780 | `ee3f23a822e17adb0a135857beed7a17bb972ba687e6908ba482981b8506869b` |
| ios | 22.15s | 23,550,382 | `a6c2310037bddf209e269d986b1d8593874834e41211ae3f394029de7db32b15` |
| android-release | 44.23s | 116,526,786 | `ad5e2b879299d6349de8540a95dcc410b64a02f2f81b770938296615d6bb6fae` |

Android Debug contains no embedded JavaScript and requires Metro; its separate exact-source export passed. Android local Release embeds Hermes bytecode, runs without Metro, and uses the unchanged generated development debug signing key. Its manifest is nondebuggable, but it is not production/store-signed. iOS Simulator Release embeds Hermes bytecode and is unsigned.

Typecheck, lint and all-platform exports passed using actual installed dependencies. The web/iOS/Android exports and both embedded release bundles contain all 13 requested source markers and 16 route keys, including published customization, original-record retry controls and the superseded-full-read marker. This proves source inclusion, not semantic runtime behavior. Both release embedded-bundle hashes differ from a1e34c7f.

Packaged native registrations include the custom device module and ImagePicker. The Android release inspection uses its actual R8 mapping and DEX class-definition table. The unchanged public development certificate SHA-256 is `fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c`. Blocked storage/audio permissions are absent; CAMERA remains for the explicit flashlight capability. iOS usage strings match the existing camera/photo configuration and contain no microphone description.

All 1,493 prior immutable files, including a1e34c7f and 10fed99 artifacts and older failures, remain intact. No device/simulator was booted, installed or launched. Native Appwrite sign-in, photo selection, torch behavior, hardware permissions, UI and accessibility remain unverified. No EAS, production signing or deployment is represented by this source checkpoint. The migration remains in progress.
