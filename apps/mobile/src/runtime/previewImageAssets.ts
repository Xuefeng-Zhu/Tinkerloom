import { ensure } from "./errors";
import type { ImageAsset } from "./types";
import type { AppSpec } from "../spec/types";

export const MAX_STATIC_PREVIEW_IMAGES = 16;
declare const previewImages: unique symbol;
/** Opaque, readonly resources minted by the host, never deserialized from AppSpec. */
export interface PreviewStaticImageAssets {
  readonly [previewImages]: true;
}
interface Assets {
  readonly images: ReadonlyMap<string, Readonly<ImageAsset>>;
  active: boolean;
  readonly listeners: Set<() => void>;
}
const grants = new WeakMap<PreviewStaticImageAssets, Assets>();
const assetIdPattern = /^[A-Za-z0-9_-]{1,128}$/;

/** This enumerates declarations only; record image values never enter a host preload. */
export function staticPreviewImageIds(spec: AppSpec): readonly string[] {
  return Object.freeze([
    ...new Set(
      spec.views.flatMap((view) =>
        view.type === "banner" && view.options?.imageAssetId
          ? [view.options.imageAssetId]
          : [],
      ),
    ),
  ]);
}

function imageSnapshot(input: ImageAsset, ownsUri: (uri: string) => boolean) {
  ensure(
    input !== null &&
      typeof input === "object" &&
      [Object.prototype, null].includes(Object.getPrototypeOf(input)),
    "invalid_preview_images",
    "Use host-owned preview images.",
  );
  const descriptors = Object.getOwnPropertyDescriptors(input);
  ensure(
    Reflect.ownKeys(descriptors).every(
      (key) =>
        typeof key === "string" &&
        ["uri", "width", "height", "alt"].includes(key) &&
        "value" in descriptors[key],
    ),
    "invalid_preview_images",
    "Use host-owned preview images.",
  );
  const { uri, width, height, alt } = input;
  ensure(
    typeof uri === "string" &&
      uri.length <= 4096 &&
      /^(blob:|file:\/\/\/)/.test(uri) &&
      !/[\s?#\u0000-\u001f]/.test(uri) &&
      ownsUri(uri) &&
      [width, height].every(
        (value) =>
          value === undefined ||
          (Number.isInteger(value) && value > 0 && value <= 2048),
      ) &&
      (alt === undefined || (typeof alt === "string" && alt.length <= 1000)),
    "invalid_preview_images",
    "Use host-owned preview images.",
  );
  return Object.freeze({
    uri,
    ...(width === undefined ? {} : { width }),
    ...(height === undefined ? {} : { height }),
    ...(alt === undefined ? {} : { alt }),
  });
}

/** Host-only minting boundary. The ownership predicate must come from its media broker. */
export function createOwnedPreviewImageAssets(
  entries: readonly (readonly [string, ImageAsset])[],
  ownsUri: (uri: string) => boolean,
): { staticImageAssets: PreviewStaticImageAssets; revoke(): void } {
  ensure(
    Array.isArray(entries) && entries.length <= MAX_STATIC_PREVIEW_IMAGES,
    "invalid_preview_images",
    "Too many preview images.",
  );
  const images = new Map<string, Readonly<ImageAsset>>();
  for (const [id, image] of entries) {
    ensure(
      assetIdPattern.test(id) &&
        !id.startsWith("preview_image_") &&
        !id.startsWith("preview_memory_") &&
        !images.has(id),
      "invalid_preview_images",
      "Use unique static image identifiers.",
    );
    images.set(id, imageSnapshot(image, ownsUri));
  }
  const staticImageAssets = Object.freeze(
    Object.create(null),
  ) as PreviewStaticImageAssets;
  const state: Assets = { images, active: true, listeners: new Set() };
  grants.set(staticImageAssets, state);
  return {
    staticImageAssets,
    revoke() {
      if (!state.active) return;
      state.active = false;
      // URI/file ownership stays with the host broker; no host IO runs here.
      (images as Map<string, Readonly<ImageAsset>>).clear();
      for (const listener of state.listeners) listener();
      state.listeners.clear();
    },
  };
}

function stateFor(value: PreviewStaticImageAssets): Assets {
  const state = value && grants.get(value);
  ensure(
    state,
    "invalid_preview_images",
    "Use host-created preview image resources.",
  );
  return state;
}
export function snapshotPreviewImages(
  assets: PreviewStaticImageAssets | undefined,
  allowedIds: readonly string[],
): ReadonlyMap<string, Readonly<ImageAsset>> {
  if (assets === undefined) return new Map();
  const state = stateFor(assets);
  if (!state.active) return new Map();
  return new Map(
    allowedIds.flatMap((id) => {
      const asset = state.images.get(id);
      return asset ? [[id, Object.freeze({ ...asset })] as const] : [];
    }),
  );
}
export function observePreviewImages(
  assets: PreviewStaticImageAssets | undefined,
  listener: () => void,
): () => void {
  if (assets === undefined) return () => {};
  const state = stateFor(assets);
  if (!state.active) return () => {};
  state.listeners.add(listener);
  return () => {
    state.listeners.delete(listener);
  };
}
