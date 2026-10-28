# React Native AppSpec semantic renderer

`RuntimeRenderer` renders an injected `RuntimeController`; it owns no Appwrite credentials or network client. `src/runtime/createPreview.ts` supplies a separate preview scope with no live/device dependencies. Components import core React Native APIs directly and use the existing safe-area package. No dependency was installed for this implementation.

All twenty-one validated view types have an explicit rendering branch:

| Views                     | Behavior                                                                                                                                                      |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| list, capacity, action    | Configured fields, compact/card presentation, authorized record actions, capacity/own-claim state and paging                                                  |
| form, details             | All eight typed fields, required/optional distinction, private image paths, eligible members and retained record revision                                     |
| board                     | Choice columns, complete-query column counts, loaded-record label, declared workflow moves through buttons and an optional drag handle                        |
| summary                   | Complete matching total and all declared choice counts, including zero counts                                                                                 |
| table                     | Complete-collection server sort, deterministic pagination, desktop columns and narrow/large-text cards                                                        |
| calendar                  | Complete month aggregate badges, independently resolved local-day UTC boundaries, selected-day paging                                                         |
| timeline                  | Timestamp order, loaded-record date groups, true undated query and continuation                                                                               |
| chart, metric             | Complete-query count/sum/average, readable exact-value legend, bar/line/donut rendering and optional metric target                                            |
| imageCards, gallery       | Opaque asset IDs resolved only by the authorized adapter; explicit unavailable state in the current live adapter                                              |
| richText, banner          | Restricted headings/bullets/quotes/strong/emphasis/code; inert links/HTML; safe tone colors, compact disclosure, responsive private image and page navigation |
| checklist                 | Typed boolean patch or declared workflow action; no direct protected-field mutation                                                                           |
| clock, timer              | Digital/analog clock; timer deadline/controller with explicit storage errors and durable live-host requirement                                                |
| deviceInfo, deviceControl | Typed bridge capabilities; synthetic preview values/controls never call the host device; live unavailable until a host bridge is supplied                     |

Navigation uses declared pages/tabs and dedicated create/edit/details pages. Legacy definitions without navigation retain a single-page path. A shared dirty-change dialog guards navigation and overlay dismissal. Unresolved commands block inputs, competing writes and leaving, with explicit same-envelope retry. A scoped host controller must survive route remounts. The renderer resets its own modal/editor state on controller-scope changes.

Configured form controls include text/multiline, switch/checkbox, choice/member selections, slider/stepper/rating, explicit-offset timestamp entry and image upload. Steps validate without writing; final Save sends one retained command. Managed workflow fields are hidden and create explicitly supplies the initial workflow choice. Patch forms also exclude assignment fields. Zero, false and unset remain distinct. Stored numeric values outside a newly configured widget range are shown and preserved during unrelated edits; changed invalid values fail instead of being clamped on load. Image-picking/uploading blocks Save, and completion is fenced to the mounted adapter scope.

The appearance helper resolves original clean/editorial/playful style defaults, density/corners/type, and contrasting accent foregrounds. Two-column/featured layouts preserve reading order and stack below 960 content pixels or at large font scales. Banner images move beside content only above 640 content pixels at normal font scale. Table/cards and text remain usable without drag gestures; the same backend-guarded workflow actions are available as buttons.

The current Function adapter advertises members only. Live private image storage, reminder state, watches, native device bridges and durable host stores remain integration work. Their UI states are explicit; a definition's capability list never silently enables them. A donut with negative aggregate values shows an explanatory exact-value legend rather than inventing a meaningful negative slice.

Local evidence is the runtime/helper suite documented in `../runtime/README.md`, TypeScript checking and scoped lint/format. Mounted browser/native interaction, drag coordinates, keyboard/screen-reader behavior, native permission/reset handling, timer recovery on real process termination, and actual cloud pagination/actions remain acceptance work after root route/API integration. No whole-migration or device-parity claim follows from this source checkpoint.

APIs were checked against the official [Expo58 reference](https://docs.expo.dev/versions/v58.0.0/), [React Native0.88 components](https://reactnative.dev/docs/components-and-apis), [accessibility](https://reactnative.dev/docs/accessibility), [PanResponder](https://reactnative.dev/docs/panresponder), [Animated](https://reactnative.dev/docs/animated), [Modal](https://reactnative.dev/docs/modal) and [Pressable](https://reactnative.dev/docs/pressable) documentation. Reference behavior comes from the original `packages/appnest_renderer` source and canonical bundled AppSpec fixtures.
