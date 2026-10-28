# Tinkerloom device module

Local Expo module for fixed torch, window brightness and keep-awake controls. Availability contains only hardware support flags; no private identifier is returned. Every effect is bound to an opaque lease and released/restored on native background/destruction callbacks. JS owns account/app consent; native code separately enforces foreground state, fixed argument shapes, hardware support and camera permission. Camera permission is requested by the host only after an explicit flashlight action. This module never captures or renders camera content.

Scaffold: official `create-expo-module@58.0.3 --local`, with the official registry fallback template `expo-module-template@58.0.9` (Expo SDK 58). Only the legacy-compatible Expo Module API and Android plugin/Podspec scaffold are used; no template React Native version or example project dependencies were installed. Template MIT notice is retained in `LICENSE`. Native source edits require CNG regeneration/autolinking and a new native build; hot reload is insufficient.

Swift syntax parsing, Podspec metadata and Expo autolinking were checked. Native compilation and hardware behavior have not yet been verified for this module.
