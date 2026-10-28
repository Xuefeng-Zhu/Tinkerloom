# Standalone encrypted-host browser probe

This harness exercises the actual browser storage adapter using only synthetic
local data. It makes no Appwrite/provider calls and must run on a separate
localhost origin from the app. Generated app.js is ignored. From the repo root:

```sh
apps/mobile/node_modules/.bin/esbuild scripts/host-storage-probe/entry.ts --bundle --platform=browser --target=es2022 --outfile=scripts/host-storage-probe/app.js
python3 -m http.server 8440 --bind 127.0.0.1 --directory scripts/host-storage-probe
```

Open localhost:8440 in Chrome. Run the storage/encryption checks (12), then
the builder CAS checks (5). Reload and run recovery (3). Read the rendered
result after each action; failures remain failures. This is standalone
IndexedDB/WebCrypto evidence, not authenticated app/native/device acceptance.
The preserved October28 receipt records the original verified bundle and
adapter source hashes. These source imports were made repository-relative
for replay, so a rebuilt harness has its own bundle hash.
