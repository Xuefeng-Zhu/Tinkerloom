import { createHostStorage as platformHostStorage } from "../host/createHostStorage";
import type { HostLifetime, HostScope } from "../host/scope";
import type { ScopedHostStorage } from "../host/storage";
import type { AppSpec } from "../spec/types";
import { decodeAppSpec } from "../spec/decode";
import { freezeValidated } from "../runtime/immutable";
import type {
  PickedImage,
  RuntimeRole,
  RuntimeTransport,
} from "../runtime/types";
import { PrivateMediaController } from "./controller";
import type { PrivateMediaOptions } from "./controller";
import type { DraftMediaAuthority, MediaPorts } from "./types";
import { MediaRecovery } from "./recovery";
import { createPrivateMediaPorts } from "./platform";
import { counter, fail, hash, id, object } from "./codec";

/** Pass authoritative saved app.draft metadata, never the unsaved editor candidate. */
export interface SavedDraftMediaSnapshot {
  appId: string;
  role: RuntimeRole;
  archived: boolean;
  pendingGeneration: boolean;
  draft: null | {
    revision: number;
    candidateHash: string;
    spec: AppSpec;
    publishedVersionId: string | null;
  };
}
export interface SavedDraftMediaContext {
  draftRevision: number;
  candidateHash: string;
}
export interface DraftMediaOptions extends Omit<
  PrivateMediaOptions,
  "recovery" | "ports" | "captureUploadContext" | "isCurrent"
> {
  current(): SavedDraftMediaSnapshot | null;
  createHostStorage?(scope: HostScope): {
    lifetime: HostLifetime;
    storage: ScopedHostStorage;
  };
  ports?: MediaPorts;
}

export function draftMediaAuthority(
  saved: SavedDraftMediaSnapshot,
): DraftMediaAuthority {
  const row = object(saved);
  if (
    (row.role !== "owner" && row.role !== "builder") ||
    row.archived !== false
  )
    fail("forbidden");
  if (row.pendingGeneration !== false) fail("media_draft_busy");
  const draft = object(row.draft);
  if (draft.publishedVersionId !== null) fail("media_draft_consumed");
  return freezeValidated({
    appId: id(row.appId),
    versionId: null,
    preview: false,
    role: row.role,
    archived: false,
    spec: decodeAppSpec(draft.spec),
    draft: {
      revision: counter(draft.revision, 2_147_483_646, 1),
      candidateHash: hash(draft.candidateHash),
    },
  });
}
function sameSavedDraft(
  authority: DraftMediaAuthority,
  saved: SavedDraftMediaSnapshot | null,
): boolean {
  try {
    const row = object(saved),
      draft = object(row.draft);
    return (
      row.appId === authority.appId &&
      row.role === authority.role &&
      row.archived === false &&
      row.pendingGeneration === false &&
      draft.publishedVersionId === null &&
      draft.revision === authority.draft.revision &&
      draft.candidateHash === authority.draft.candidateHash
    );
  } catch {
    return false;
  }
}
/** Media-only authority: there is no RuntimeAdapter, published version or record API. */
export class DraftMediaController extends PrivateMediaController {
  private unlinkParent?: () => void;
  readonly savedContext: Readonly<SavedDraftMediaContext>;
  constructor(
    readonly draftAuthority: DraftMediaAuthority,
    transport: RuntimeTransport,
    lifetime: HostLifetime,
    options: PrivateMediaOptions,
  ) {
    super(draftAuthority, transport, lifetime, options);
    this.savedContext = Object.freeze({
      draftRevision: draftAuthority.draft.revision,
      candidateHash: draftAuthority.draft.candidateHash,
    });
  }
  bindParent(parent: HostLifetime) {
    this.unlinkParent = parent.onDispose(() => this.dispose());
  }
  uploadDraft(image: PickedImage) {
    return this.upload(
      { draftRevision: this.savedContext.draftRevision },
      image,
    );
  }
  override dispose() {
    super.dispose();
    this.unlinkParent?.();
    this.unlinkParent = undefined;
    this.lifetime.dispose();
  }
}

/** Owns a distinct child host lifetime; sharing the parent's lifetime is rejected. */
export function createDraftMediaController(
  saved: SavedDraftMediaSnapshot,
  transport: RuntimeTransport,
  parent: HostLifetime,
  options: DraftMediaOptions,
): DraftMediaController {
  parent.assertActive();
  if (!options.privateMedia) return fail("media_unavailable");
  const authority = draftMediaAuthority(saved);
  const readCurrent = () => {
    try {
      return options.current();
    } catch {
      return null;
    }
  };
  if (
    authority.appId !== parent.scope.appId ||
    !sameSavedDraft(authority, readCurrent())
  )
    return fail("media_context_changed");
  const host = (options.createHostStorage ?? platformHostStorage)(parent.scope);
  let ports: MediaPorts | undefined;
  try {
    if (
      host.lifetime === parent ||
      host.lifetime.key !== parent.key ||
      host.storage.lifetime !== host.lifetime
    )
      fail("media_scope_mismatch");
    ports = options.ports ?? createPrivateMediaPorts(host.lifetime);
    const controller = new DraftMediaController(
      authority,
      transport,
      host.lifetime,
      {
        ...options,
        recovery: new MediaRecovery(host.storage, "private-draft-media-v1"),
        ports,
        isCurrent: () => {
          const current =
            parent.active && sameSavedDraft(authority, readCurrent());
          if (!current) host.lifetime.dispose();
          return current;
        },
      },
    );
    controller.bindParent(parent);
    void controller.recover().catch(() => {}); // local-only; never replay a command
    return controller;
  } catch {
    try {
      ports?.dispose();
    } catch {}
    if (host.lifetime !== parent) host.lifetime.dispose();
    return fail("media_local_unavailable");
  }
}

/** Explicit selection only; it does not edit a definition or save/publish anything. */
export async function selectReadyDraftMedia(
  controller: DraftMediaController,
  destination: SavedDraftMediaContext,
  isCurrent: () => boolean,
  select: (opaqueAssetId: string) => void,
): Promise<boolean> {
  const revision = counter(destination.draftRevision, 2_147_483_646, 1),
    candidate = hash(destination.candidateHash);
  const matches = () =>
    isCurrent() &&
    controller.savedContext.draftRevision === revision &&
    controller.savedContext.candidateHash === candidate;
  if (!matches()) fail("media_context_changed");
  const ready = await controller.poll();
  if (!ready) return false;
  if (!matches()) fail("media_context_changed");
  select(ready);
  return true;
}
