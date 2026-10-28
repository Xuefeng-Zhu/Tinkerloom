# React Native verification - October 27, 2026

The following checks were run against the initial React Native migration. They do not cover full AppNest feature parity.

- `npm run typecheck`: passed.
- `npm run lint`: passed.
- `npm test`: 24 passed. These cover injected Appwrite responses, retained creation commands, account/workspace response races, auth response-loss recovery without repeating mutations, validation, local preview isolation, and reset.
- `npx expo export --platform all`: passed for web, iOS, and Android. Native output is Hermes JavaScript bytecode; no Xcode/Gradle compilation or device installation was performed.
- The exported web app was served locally and exercised through the browser. Verified the template gallery, task required-field error, sample creation, completion toggle, title/field-label customization, editing retained values, and reset back to the original three task records.
- Layout measurements: viewport/document scroll widths matched at 320, 768, 1024, and 1440 pixels. A task card and editor were exercised at 320 pixels. Keyboard Tab reached a template-gallery control. This is bounded responsive/accessibility evidence, not a full accessibility audit.
- Browser console captured no errors during that local preview walkthrough.
- Expo Router gallery/template navigation and direct reload at `/preview/tasks` passed against the final local preview server. The initial static server did not fall back to the app entry page; `preview:web` now uses SPA fallback and binds only to loopback.

No live Appwrite account, Function, permission, persistence, or worker behavior was exercised. Unit tests use fake SDK adapters and in-memory preview data. Pending cloud provisioning/deployment and public push approvals were not treated as granted by the frontend framework change.
