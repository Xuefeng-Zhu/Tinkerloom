# Workbench return flow and pinned pages

Returning users see their accessible apps and own private drafts before the creation section. Apps retain the backend's newest-created ordering; this is not a last-opened usage history. Creation options start collapsed for returning users. The top **New app** shortcut expands and scrolls to them without creating an app. A successfully loaded, empty, unfiltered workspace keeps the expanded starter/name onboarding. Pending outcome and created-app notices retain priority.

**Show pinned apps only** now reads `spec.launcher` with `pinnedOnly: true`. The controller owns the selected filter, immediately clears its apps/cursor on a change, and sends the same boolean on every app page and refresh. Draft discovery remains author-private and independent of this filter. Cursors are not reused between the filtered and unfiltered catalogs. Old initial/page results and failures are fenced after a newer filter/read starts. A pinned response containing an unpinned app is rejected rather than silently filtered.

Pinning still uses the durable retained command with its original preference revision and operation ID. Changing the catalog filter never replays that command. An explicit successful retry reloads the currently selected catalog; unpinning the last visible pin therefore leaves an honest pinned-empty state.

Shared `Choices` radios and the launcher `Toggle` retain native `accessibilityState.checked/disabled` and also pass explicit `aria-checked`/`aria-disabled`, supported by the installed RN0.88 types. RNWeb0.21.4 maps these aliases to DOM state. Targets and visual selection remain unchanged.

Verification: nine new groups cover server-filter pagination beyond the loaded page; rapid filter races and late failures; malformed/foreign responses; exact pin receipt recovery; access/dispose fencing; actual React Native Web server-rendered checked/disabled attributes; returning hierarchy and first-time/filtered-empty content. The web render uses the installed RNWeb and Safe Area web entrypoints and is not browser interaction or native screen-reader proof.

After merge/export, verify browser scrolling from the **New app** shortcut, keyboard navigation/radio and checkbox state, pin/unpin while filtered, and loaded-page continuation. Native assistive-technology/device proof remains separate.

API sources: local `appwrite_backend/LIFECYCLE.md` and `lib/spec_lifecycle.dart` (`spec.launcher` boolean validation and filter-scoped cursor). UI APIs were checked against [Expo58](https://docs.expo.dev/versions/v58.0.0/), [RN0.88 accessibility](https://reactnative.dev/docs/accessibility), [ScrollView](https://reactnative.dev/docs/scrollview), and the installed matching type/DOM implementations. No backend, dependency, route, renderer form, provider, Cloud or native changes belong to this patch.
