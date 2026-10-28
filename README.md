# Tinkerloom

Tinkerloom is an early-stage rewrite of AppNest using Flutter and Appwrite. Its goal is to let people build and use shared mini-apps from declarative definitions.

**Migration status: incomplete.** This repository is being assembled. The existing AppNest application has not yet been migrated to Appwrite, and its user accounts, data, sharing rules, concurrency controls, and reminders have not been transferred or verified here. Do not treat this repository as a production-ready replacement.

## Repository layout

- `packages/` contains the shared AppNest definition language and renderer copied from the committed AppNest source. Their package names have not yet been migrated.
- `legacy_appnest/` is a committed-source snapshot retained as a reference for behavior and migration. It is the original Serverpod implementation, not the Tinkerloom backend.
- `appwrite_backend/` contains the first Appwrite Function: owner-only workspace and app-shell creation and listing.
- `appwrite_flutter/` contains an initial Flutter client for Appwrite authentication and those operations.

The Flutter client does not yet support the mini-app builder or runtime. The Appwrite slice has not been verified against a running service. See the READMEs in the Appwrite directories for setup and test limitations. No Appwrite project or infrastructure is created by this repository.
