# Posthoc offline GLM multistep assertion diagnostic

Generated: 2026-10-08T10:25:24.440722Z. Input checkpoint updated: 2026-10-08T10:22:38.092014Z (blocked). SHA256 `9f83e60ae88fe28d3e30da0102deb4ea69dadcd973ae8bafb638ee34c9f3f771`. Run `e7cd449878d1973a1e973cee86dcaa68dd2030325283fb0006b8c085121bb84a`.

Every scored source hash matched the checkpoint manifest. No provider calls, checkpoint writes, scored source edits or primary score changes were made.

`z-ai/glm-5.3` / `create-multistep-form` remains **failed** in the frozen primary benchmark. Only saved responses are replayed below; attempt 2 timed out. Production checks include strict AppSpec parsing, required-capability compilation, generated-experience validation and request-derived GenerationRequirements.

| Attempt | Strict parse | Production checks | Added capabilities | Fixed assertions | Fixed assertions after diagnostic-only explicit image control |
| --- | --- | --- | --- | --- | --- |
| 1 | true | true | [] | false | true |
| 3 | true | true | [] | false | true |

The fixed scenario requires an explicit `imageUpload` control entry on the image field. The isolated in-memory diagnostic adds only that entry. Its results do not amend the responses or primary scores.

Renderer source dispatches every image field to `_imageControl` before consulting its explicit control kind (`packages/appnest_renderer/lib/src/editor.dart:417`). That widget presents Choose/Replace image (`:799`) and calls the adapter's `uploadImage` method (`:850`). The missing explicit configuration is therefore not source-level evidence that the typed image upload UI would be absent. The scenario assertion is stricter than the renderer's default image behavior.

The one-entry in-memory insertion only isolates the failing fixed assertion; it is not production compilation, a new model response, a score correction, or renderer/device/upload execution evidence. No rendered screen, authenticated asset upload, persistence or device behavior was verified. The JSON records response hashes and per-attempt results; `offline_glm_multistep_diagnostic.dart` reproduces this check from the local saved checkpoint.

