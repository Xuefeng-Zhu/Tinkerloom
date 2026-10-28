# Portable AppSpec contract

This is the pure Dart AppNest definition contract bundled inside the Appwrite Function archive. It has no Flutter or Serverpod dependency. The initial source is identical to `packages/appnest_spec` in Tinkerloom at commit `2234d11`, which was checked against the current AppNest source before copying.

The package is standalone: workspace resolution is removed and its minimum Dart SDK is 3.11, matching the Cloud Function runtime. Formatting follows that language version. The original validator, capability gates, semantic patches, compatibility checks, canonical hashes, schema, templates, fixtures, and 87 tests are retained.

The runtime dependency is pinned through the enclosing Function's lockfile. Library development dependencies resolve for the SDK used by its separate CI job.

Passing these contract tests establishes parser portability only. It does not establish the Appwrite storage/action implementation, React Native widget implementation, native-device behavior, or full migration acceptance. Those requirements are tracked in `docs/FULL_MIGRATION.md` at the repository root.

The isolated engine foundation intentionally hardens two invalid-input cases in
`FieldSpec`: strict no-rollover timestamps (including aggregate bucket boundaries)
and explicit integer/number magnitude comparisons that cannot overflow on the
minimum machine integer. Valid fixture canonical hashes remain unchanged; all
87 retained tests pass. `SPEC_ENGINE.md` at the enclosing Function root records
these changes and their focused engine regressions. They must be reviewed and
verified on the selected Cloud runtime before deployment acceptance is claimed.
