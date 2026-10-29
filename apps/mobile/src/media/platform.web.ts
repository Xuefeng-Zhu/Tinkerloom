import type { HostLifetime } from "../host/scope";
import type { MediaPorts, ImageResource } from "./types";
import { fail } from "./codec";
import { collectPickedImage } from "./picker";

export function createPrivateMediaPorts(lifetime: HostLifetime): MediaPorts {
  const resources = new Set<ImageResource>();
  let closed = false;
  let cancelPicker: (() => void) | undefined;
  const guard = () => {
    lifetime.assertActive();
    if (closed) fail("disposed");
  };
  return {
    async sha256(bytes) {
      guard();
      const result = await crypto.subtle.digest(
        "SHA-256",
        Uint8Array.from(bytes),
      );
      guard();
      return Array.from(new Uint8Array(result), (b) =>
        b.toString(16).padStart(2, "0"),
      ).join("");
    },
    async pick() {
      guard();
      if (cancelPicker) fail("media_busy");
      // Expo's Web picker decodes the selected image before returning the File.
      // Keep the original opaque until its size is checked: no original blob URL,
      // Image decode, EXIF extraction, filename persistence or full-file read.
      const file = await new Promise<globalThis.File | null>(
        (resolve, reject) => {
          const input = document.createElement("input");
          input.type = "file";
          input.accept = "image/jpeg,image/png,image/webp";
          input.multiple = false;
          input.style.display = "none";
          let settled = false;
          let focusTimer: ReturnType<typeof setTimeout> | undefined;
          const finish = (
            selected: globalThis.File | null,
            error?: unknown,
          ) => {
            if (settled) return;
            settled = true;
            clearTimeout(focusTimer);
            window.removeEventListener("focus", onFocus);
            input.removeEventListener("change", onChange);
            input.removeEventListener("cancel", onCancel);
            input.remove();
            cancelPicker = undefined;
            if (error) reject(error);
            else resolve(selected);
          };
          const onChange = () => {
            if (!input.files?.length) finish(null);
            else if (input.files.length !== 1) {
              try {
                fail("media_unsupported");
              } catch (error) {
                finish(null, error);
              }
            } else finish(input.files[0]);
          };
          const onCancel = () => finish(null);
          const onFocus = () => {
            // Fallback for browsers that do not emit the input's cancel event.
            focusTimer = setTimeout(() => {
              if (!input.files?.length) finish(null);
            }, 1000);
          };
          cancelPicker = onCancel;
          input.addEventListener("change", onChange);
          input.addEventListener("cancel", onCancel);
          window.addEventListener("focus", onFocus);
          document.body.appendChild(input);
          try {
            input.click();
          } catch (error) {
            finish(null, error);
          }
        },
      );
      guard();
      if (!file) return null;
      let offset = 0;
      return collectPickedImage(
        async (maximum) => {
          if (offset >= file.size) return new Uint8Array();
          const chunk = new Uint8Array(
            await file.slice(offset, offset + maximum).arrayBuffer(),
          );
          offset += chunk.length;
          return chunk;
        },
        guard,
        [file.size],
        file.type,
      );
    },
    async image(bytes, contentType) {
      guard();
      const uri = URL.createObjectURL(
        new Blob([Uint8Array.from(bytes)], { type: contentType }),
      );
      const resource: ImageResource = {
        uri,
        dispose() {
          URL.revokeObjectURL(uri);
          resources.delete(resource);
        },
      };
      resources.add(resource);
      return resource;
    },
    dispose() {
      if (closed) return;
      closed = true;
      cancelPicker?.();
      for (const resource of [...resources]) resource.dispose();
    },
  };
}
