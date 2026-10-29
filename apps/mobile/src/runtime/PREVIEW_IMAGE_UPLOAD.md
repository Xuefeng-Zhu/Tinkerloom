# Memory-only preview image bytes

`PreviewRuntimeAdapter.uploadImage(PickedImage)` validates and copies accepted original bytes into that single preview's private memory map. It returns an opaque `preview_memory_<session>_<sequence>` ID. `readImage(id)` returns a `data:<verified MIME>;base64,...` URI containing those exact accepted bytes and their allocation-header width/height. Mutating the caller's input afterward cannot change the retained image. No constant sample is returned for an uploaded image.

This path performs no network, storage, native picker, permission request, host-resource creation, SDK call, decoder, transcoding or metadata removal. `pickImage` remains explicitly unavailable; the existing UI button still says **Use example image** and selects the separate synthetic `preview_image_0` path. The adapter advertises `imageUpload` because real byte ingestion is implemented; this does not advertise picking, Cloud media or sanitized output. It never bypasses the authenticated live media broker/sanitizer and cannot make a preview record live.

The local limits are:

- Each original: 1 byte–5 MiB, JPEG/PNG/WebP only, MIME must match the detected container.
- Allocation headers: each side 1–8192 and at most 16,000,000 pixels; animation is rejected.
- One preview: at most 16 retained memory images, 8 MiB retained original bytes and 16,000,000 total declared pixels. Borrowed host static resources remain separately bounded/owned by their broker.
- PNG preflight counts decompressed scanlines without retaining the raster, using a 32 KiB DEFLATE history window. The derived expanded-byte maximum is 16,000,000 × 8 + 16,384 Adam7 row-filter bytes for 16-bit RGBA, not a retained decoded-image allocation.

Data URIs are generated on read in bounded base64 chunks and are not cached by the adapter. Their string size is necessarily about four thirds of the original byte count; callers/native rendering may retain their own returned strings/decoded pixels. The 8 MiB counter measures adapter-owned original bytes, not the JavaScript VM or operating system's total memory. Disposal overwrites the owned byte arrays and clears all IDs/counters; it cannot revoke a data URI string already copied by an external caller. The host must unmount/clear its renderer when the preview closes, as it does for other private state.

Presentation changes keep the same memory image map along with records, exact receipts, cursors and navigation. Semantic changes dispose the old sandbox and start another. The session prefix differs, so an old memory ID cannot resolve to a new session's image. Unknown IDs reject, and reads/uploads after disposal reject. Malformed or over-budget uploads cannot allocate an ID or fabricate a successful sample image. `preview_memory_` and `preview_image_` namespaces cannot be lent through a host static-image grant.

## Preflight boundaries

The pure TypeScript preflight is based on the allocation/container checks in `appwrite_backend/lib/image_preflight.dart`. Unlike that backend, it keeps original bytes, does not normalize JPEG tables, strip metadata, bake orientation, invoke a pinned decoder or verify final decoded pixels. Its acceptance is deliberately more conservative for metadata that the live worker strips before decoding:

- JPEG: bounded segments, supported 8-bit baseline/extended/progressive frame, one frame, component/sampling/quantization/Huffman/scan structure, no dimension redefinition, explicit end of image. JFIF and fixed Adobe transform markers are accepted; original EXIF/XMP/ICC and other APP containers are refused. Valid quantization FFxx values are interpreted within fully checked table boundaries, preserving all 100 pinned encoder-quality fixtures unchanged. Comments are retained when structurally safe.
- PNG: chunk boundaries/counts/CRC/order, color-depth/palette/transparency rules, no APNG, exact zlib/DEFLATE output count and Adler checksum, scanline filter range, Adam7 pass accounting, and no trailing/incomplete compressed stream. Compressed metadata, EXIF and unknown critical/container chunks are refused. Allowed uncompressed text is retained exactly; it is **not sanitized**.
- WebP: exact RIFF size, bounded unique still-image bitstream, canvas/bitstream dimension agreement, supported VP8/VP8L/alpha container shape, no animated chunks/flags, metadata containers or scale-bit surprises.

These checks establish bounded header/container acceptance, not a complete JPEG/WebP entropy decoder or browser/native pixel-display proof. A platform decoder may still reject a structurally accepted stream. The returned image is labeled **Local preview image (original bytes; not uploaded)**. Real Cloud storage always uses its independent worker's complete decode/transcode/sanitization checks.

## Verification

`previewImageFixtures.ts` contains 109 small synthetic vectors exported using the existing pinned Dart image package and literals from `image_resource_test.dart`: all 100 quality levels of the same 3×2 pattern, baseline/gray JPEG, three PNG channel variants, progressive/CMYK JPEG and lossy/lossless WebP. Its source-test SHA-256 is recorded in the fixture file. Every vector is uploaded, read back byte-for-byte, checked for dimensions/MIME and verified independent of subsequent caller-buffer mutation. They are public synthetic pixels, not user images.

The 121 new groups also cover the backend's palette/low-bit/16-bit/Adam7 layouts, split IDAT and decompression bombs, malformed chunks/CRC/zlib/checksum/Huffman containers, JPEG allocation/table/scan attacks, WebP animation/duplicate streams/canvas/metadata attacks, MIME/empty/oversized/shared-buffer rejection, exact byte/pixel/asset budget boundaries, base64 tail sizes, and presentation/disposal/semantic-reset isolation. An independent Node zlib encoder supplies 42 stored/fixed/dynamic/Huffman/RLE streams across block/window sizes; the pure validator reproduces each byte using bounded history. Node APIs are test-only and no new dependency is added.

The isolated client snapshot passes all 453 tests, typecheck, Expo lint and owned-file formatting. These are local source and test proofs. No Cloud, browser pixels, native/device operations, provider calls or deployment was performed for this follow-up. The earlier static-image scope/late-result/prototype/fixture tests remain intact; the old fake-byte rejection check now requires a specific malformed-image rejection alongside the actual valid roundtrip tests.
