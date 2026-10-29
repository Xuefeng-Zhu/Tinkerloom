import type { ScopedHostStorage } from "../host/storage";
import type { HostLifetime } from "../host/scope";
import type {
  RuntimeAdapter,
  RuntimeTransport,
  PickedImage,
  RuntimeRecord,
  RuntimeCommand,
} from "../runtime/types";
import type { ActionSpec, RecordQuery, AggregateQuery } from "../spec/types";
import { PrivateMediaController } from "./controller";
import type { PrivateMediaOptions } from "./controller";
import type {
  MediaPorts,
  MediaUploadContext,
  RecordMediaUploadContext,
} from "./types";
import { MediaRecovery } from "./recovery";
import { createPrivateMediaPorts } from "./platform";
import { fail } from "./codec";

export interface PrivateMediaWrapperOptions extends Omit<
  PrivateMediaOptions,
  "recovery" | "ports"
> {
  storage: ScopedHostStorage;
  ports?: MediaPorts;
}
export interface MediaRuntimeAdapter extends RuntimeAdapter {
  readonly media?: PrivateMediaController;
  setActive?(active: boolean): void;
  uploadImage(
    image: PickedImage,
    context?: RecordMediaUploadContext,
  ): Promise<string>;
}
/** Compose around, never replace, the authenticated base or isolated preview. */
export function withPrivateMedia(
  base: RuntimeAdapter,
  transport: RuntimeTransport,
  lifetime: HostLifetime,
  options: PrivateMediaWrapperOptions,
): MediaRuntimeAdapter {
  if (base.preview || !options.privateMedia) return base;
  let ports: MediaPorts | undefined;
  let media: PrivateMediaController;
  try {
    ports = options.ports ?? createPrivateMediaPorts(lifetime);
    media = new PrivateMediaController(base, transport, lifetime, {
      ...options,
      recovery: new MediaRecovery(options.storage),
      ports,
    });
  } catch {
    try {
      ports?.dispose();
    } catch {}
    return fail("media_local_unavailable");
  }
  void media.recover().catch(() => {
    /* Recovery failure remains visible; no mutation is sent. */
  });
  let closed = false;
  const forward = async <T>(work: () => Promise<T>) => {
    try {
      lifetime.assertActive();
      if (closed) fail("disposed");
      const result = await work();
      lifetime.assertActive();
      return result;
    } catch (error) {
      throw media.handleFailure(error);
    }
  };
  return {
    get appId() {
      return base.appId;
    },
    get versionId() {
      return base.versionId;
    },
    get spec() {
      return base.spec;
    },
    get preview() {
      return base.preview;
    },
    get role() {
      return base.role;
    },
    get archived() {
      return base.archived;
    },
    get approvedRuleIds() {
      return base.approvedRuleIds;
    },
    get features() {
      const features = new Set(base.features);
      features.delete("imageRead");
      features.delete("imageUpload");
      if (!closed && lifetime.active && !media.getSnapshot().accessDenied) {
        features.add("imageRead");
        if (!base.archived && base.role !== "viewer")
          features.add("imageUpload");
      }
      return features;
    },
    media,
    query: (collectionId: string, query: RecordQuery) =>
      forward(() => base.query(collectionId, query)),
    get: (recordId: string) => forward(() => base.get(recordId)),
    summary: (collectionId: string, query: RecordQuery, field: string) =>
      forward(() => base.summary(collectionId, query, field)),
    aggregate: (
      collectionId: string,
      query: RecordQuery,
      aggregate: AggregateQuery,
    ) => forward(() => base.aggregate(collectionId, query, aggregate)),
    execute: (command: RuntimeCommand) => forward(() => base.execute(command)),
    permits: (action: ActionSpec, record?: RuntimeRecord) =>
      lifetime.active && !closed && base.permits(action, record),
    members: () => forward(() => base.members()),
    reminderState: (recordId: string) =>
      forward(() => base.reminderState(recordId)),
    readImage: (assetId: string) => media.read(assetId),
    pickImage: () => media.pickImage(),
    uploadImage: async (
      image: PickedImage,
      context?: RecordMediaUploadContext,
    ) => {
      const captured: MediaUploadContext | undefined =
        context ?? options.captureUploadContext?.();
      if (!captured) return fail("media_context_required");
      return media.upload(captured, image);
    },
    watch: (listener: () => void) =>
      lifetime.active && !closed ? base.watch(listener) : () => {},
    setActive: (active: boolean) => {
      if (!active || (lifetime.active && !closed))
        (
          base as RuntimeAdapter & { setActive?(active: boolean): void }
        ).setActive?.(active);
    },
    dispose: () => {
      if (closed) return;
      closed = true;
      media.dispose();
      base.dispose();
    },
  };
}
