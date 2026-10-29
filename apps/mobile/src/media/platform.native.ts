import * as ImagePicker from "expo-image-picker";
import * as Crypto from "expo-crypto";
import { Directory, File, FileMode, Paths } from "expo-file-system";
import type { HostLifetime } from "../host/scope";
import type { MediaPorts, ImageResource } from "./types";
import { fail } from "./codec";
import { collectPickedImage } from "./picker";
let initialized = false;

export function createPrivateMediaPorts(lifetime: HostLifetime): MediaPorts {
  lifetime.assertActive();
  const root = new Directory(Paths.cache, "tinkerloom-private-images");
  // The first media scope after process restart removes prior ephemeral files.
  // Later live scopes use separate random directories and never evict each other.
  if (!initialized) {
    if (root.exists) root.delete();
    root.create({ idempotent: true, intermediates: true });
    initialized = true;
  }
  const directory = new Directory(root, Crypto.randomUUID());
  directory.create({ intermediates: true, idempotent: true });
  const resources = new Set<ImageResource>(),
    handles = new Set<{ close(): void }>();
  let closed = false;
  const guard = () => {
    lifetime.assertActive();
    if (closed) fail("disposed");
  };
  return {
    async sha256(bytes) {
      guard();
      const digest = await Crypto.digest(
        Crypto.CryptoDigestAlgorithm.SHA256,
        Uint8Array.from(bytes),
      );
      guard();
      return Array.from(new Uint8Array(digest), (b) =>
        b.toString(16).padStart(2, "0"),
      ).join("");
    },
    async pick() {
      guard();
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ["images"],
        allowsMultipleSelection: false,
        allowsEditing: false,
        quality: 1,
        base64: false,
        exif: false,
      });
      let handle: ReturnType<File["open"]> | undefined;
      try {
        guard();
        if (result.canceled) return null;
        if (result.assets.length !== 1) fail("media_unsupported");
        const selected = result.assets[0];
        if (!/^(file:\/\/|content:\/\/)/.test(selected.uri))
          fail("media_unsupported");
        const file = new File(selected.uri);
        const sizes = [selected.fileSize, file.size];
        return await collectPickedImage(
          async (maximum) => {
            // Open lazily: known oversized files never even acquire a read handle.
            if (!handle) {
              handle = file.open(FileMode.ReadOnly);
              handles.add(handle);
            }
            return handle.readBytes(maximum);
          },
          guard,
          sizes,
          selected.mimeType,
        );
      } finally {
        if (handle) {
          handles.delete(handle);
          try {
            handle.close();
          } catch {}
        }
        // A picker may finish after scope closure. Clean up its app cache copy
        // even then; never remove a content:// URI or a photo-library original.
        const prefix = Paths.cache.uri.replace(/\/+$/, "") + "/ImagePicker/";
        for (const selected of result.assets ?? []) {
          if (!selected.uri.startsWith(prefix)) continue;
          try {
            const copy = new File(selected.uri);
            if (copy.exists) copy.delete();
          } catch {}
        }
      }
    },
    async image(bytes, contentType) {
      guard();
      const file = new File(
        directory,
        `${Crypto.randomUUID()}.${contentType === "image/png" ? "png" : "jpg"}`,
      );
      try {
        file.create({ overwrite: false });
        file.write(bytes);
        if (file.size !== bytes.length) fail("media_storage_failed");
        guard();
      } catch (error) {
        try {
          if (file.exists) file.delete();
        } catch {}
        throw error;
      }
      const resource: ImageResource = {
        uri: file.uri,
        dispose() {
          try {
            if (file.exists) file.delete();
          } finally {
            resources.delete(resource);
          }
        },
      };
      resources.add(resource);
      return resource;
    },
    dispose() {
      if (closed) return;
      closed = true;
      for (const handle of handles) {
        try {
          handle.close();
        } catch {}
      }
      handles.clear();
      for (const resource of [...resources]) {
        try {
          resource.dispose();
        } catch {}
      }
      try {
        if (directory.exists) directory.delete();
      } catch {}
    },
  };
}
