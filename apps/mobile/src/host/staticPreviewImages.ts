import type { HostLifetime } from "./scope";
import type { ImageAsset } from "../runtime/types";
import type { AppSpec } from "../spec/types";
import { decodeAppSpec } from "../spec/decode";
import { freezeValidated } from "../runtime/immutable";
import { ensure } from "../runtime/errors";
import {
  createOwnedPreviewImageAssets,
  MAX_STATIC_PREVIEW_IMAGES,
  staticPreviewImageIds,
  snapshotPreviewImages,
} from "../runtime/previewImageAssets";
import type { PreviewStaticImageAssets } from "../runtime/previewImageAssets";

export interface StaticPreviewImageResult {
  readonly staticImageAssets: PreviewStaticImageAssets;
  readonly unavailableAssetIds: readonly string[];
  readonly closed: boolean;
}
export interface StaticPreviewImageOptions {
  lifetime: HostLifetime;
  readImage: (assetId: string) => Promise<ImageAsset>;
  ownsUri: (uri: string) => boolean;
  isCurrent: (snapshotIdentity: string) => boolean;
}
/** Authenticated reads happen here, outside the preview factory and its object graph. */
export class StaticPreviewImagePreloader {
  private epoch = 0;
  private closed = false;
  private revoke = () => {};
  private readonly removeLifetimeListener: () => void;
  private readonly options: Readonly<StaticPreviewImageOptions>;
  constructor(options: StaticPreviewImageOptions) {
    this.options = Object.freeze({ ...options });
    options.lifetime.assertActive();
    this.removeLifetimeListener = options.lifetime.onDispose(() =>
      this.dispose(),
    );
  }
  async load(
    input: AppSpec,
    snapshotIdentity: string,
  ): Promise<StaticPreviewImageResult> {
    ensure(
      typeof snapshotIdentity === "string" &&
        snapshotIdentity.length > 0 &&
        snapshotIdentity.length <= 1024,
      "invalid_preview_images",
      "A current preview snapshot is required.",
    );
    const epoch = ++this.epoch;
    this.revoke();
    this.revoke = () => {};
    const spec = freezeValidated(decodeAppSpec(input));
    const ids = staticPreviewImageIds(spec);
    ensure(
      ids.length <= MAX_STATIC_PREVIEW_IMAGES,
      "invalid_preview_images",
      "Too many preview images.",
    );
    const current = () =>
      !this.closed &&
      this.options.lifetime.active &&
      epoch === this.epoch &&
      this.options.isCurrent(snapshotIdentity);
    const entries: (readonly [string, ImageAsset])[] = [],
      unavailable = new Set<string>();
    let next = 0;
    await Promise.all(
      Array.from({ length: Math.min(3, ids.length) }, async () => {
        while (next < ids.length && current()) {
          const id = ids[next++];
          try {
            const image = await this.options.readImage(id);
            if (!current()) break;
            // Validate before keeping even a partial result. A read cannot inject a URL.
            const checked = createOwnedPreviewImageAssets(
              [[id, image]],
              this.options.ownsUri,
            );
            const snapshot = snapshotPreviewImages(checked.staticImageAssets, [
              id,
            ]).get(id)!;
            checked.revoke();
            entries.push([id, snapshot]);
          } catch {
            if (current()) unavailable.add(id);
          }
        }
      }),
    );
    if (!current()) {
      const empty = createOwnedPreviewImageAssets([], () => false);
      empty.revoke();
      return Object.freeze({
        staticImageAssets: empty.staticImageAssets,
        unavailableAssetIds: Object.freeze([]),
        closed: true,
      });
    }
    // Cache eviction/revocation can happen during another read; recheck every URI.
    const retained = entries.filter(([id, image]) => {
      if (this.options.ownsUri(image.uri)) return true;
      unavailable.add(id);
      return false;
    });
    const grant = createOwnedPreviewImageAssets(retained, this.options.ownsUri);
    this.revoke = grant.revoke;
    return Object.freeze({
      staticImageAssets: grant.staticImageAssets,
      unavailableAssetIds: Object.freeze(
        ids.filter((id) => unavailable.has(id)),
      ),
      closed: false,
    });
  }
  dispose() {
    if (this.closed) return;
    this.closed = true;
    this.epoch++;
    this.revoke();
    this.revoke = () => {};
    this.removeLifetimeListener();
  }
}
