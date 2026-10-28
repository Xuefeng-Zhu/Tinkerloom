# React Native migration status

The primary frontend is `apps/mobile`, built with React Native and Expo. Appwrite Functions remain the trusted backend. The initial backend implementation is Dart; React Native does not require a Node backend.

## Implemented

- Native and browser Appwrite SDK adapters with validated public configuration and safe error messages.
- Account sign-in/sign-up/session restoration/sign-out.
- Owned workspaces and empty app-shell creation/listing through the existing Function API.
- Explicit same-command retries after an unknown creation result; late account/workspace responses are fenced.
- Isolated local Notes, Tasks, and Reading previews with form validation, editing, checkboxes/choices, title/label customization, and reset.
- Native React Native layouts, keyboard-aware forms, safe areas, accessible input labels and controls, and responsive web/tablet layouts.

## Remaining migration

The TypeScript preview model is a small independent subset. The original Dart AppSpec validator/schema and renderer still require a deliberate parity port and fixture compatibility tests. The full visual/AI builder, live record queries/actions/aggregates, revisions/receipts, multi-user sharing and grant revocation, capacity constraints, private media, durable reminder/outbox workers, and device capabilities are not implemented in the React Native/Appwrite replacement.

Existing accounts and records have not been migrated. The retained legacy code and historical evidence do not establish acceptance of the new implementation.

## Verification boundary

TypeScript, unit tests, and platform bundle exports can be run locally without an Appwrite account. Unit tests use fake SDK responses or in-memory preview state. Live two-account authorization, fresh-session persistence, real Function execution, service permission denial, concurrency, and recovery need an isolated Appwrite development project and are pending.

Xcode/Gradle compilation, simulator/device interaction, release signing, performance, and full accessibility acceptance are separate checks. No paid service, production deployment, public code push, or credential creation is required by the local commands.

The initial Expo dependency tree reports upstream audit advisories in Expo and local-preview tooling. The suggested npm automatic fix downgrades Expo across major versions and was not applied. The local preview server binds only to loopback and disables compression. Review upstream compatible fixes before production delivery.
