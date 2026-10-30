# Appwrite verification

Routine development uses the offline preview and tests described in the [development guide](DEVELOPMENT.md). The test suites use in-memory stores and local transports; they do not establish native-device or production behavior.

The connected development app uses real Appwrite resources. Function executions can each perform multiple database operations. Keep refresh manual, avoid broad live probes, and obtain explicit authorization before provisioning, creating additional synthetic accounts or records, deploying changes, or enabling periodic background work.

A bounded SDK/service check has verified a synthetic Notes record through save and reload. It does not prove native UI, hardware permissions, real AI-provider usage, or production readiness. Historical verification records are retained in the [evidence directory](evidence/); do not rerun bootstrap or recovery tools as routine tests.

Never put credentials in documentation, client builds, logs, or version control. Preserve ignored local credentials and recovery journals.
