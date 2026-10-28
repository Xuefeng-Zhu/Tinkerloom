import {
  decodeRuntimeManifest,
  type RuntimeManifest,
} from "../runtime/functionAdapter";
import { ensure } from "../runtime/errors";
import { runtimeJsonSnapshot } from "../runtime/json";
import { freezeValidated } from "../runtime/immutable";

export const row = (value: unknown): Record<string, unknown> => {
  ensure(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "invalid_response",
    "The server returned an invalid object.",
  );
  return value as Record<string, unknown>;
};
export const text = (value: unknown, max = 4096): string => {
  ensure(
    typeof value === "string" && value.length > 0 && value.length <= max,
    "invalid_response",
    "The server returned invalid text.",
  );
  return value;
};
export const count = (value: unknown): number => {
  ensure(
    Number.isSafeInteger(value) && (value as number) >= 0,
    "invalid_response",
    "The server returned an invalid revision.",
  );
  return value as number;
};
export const strings = (value: unknown): string[] => {
  ensure(
    Array.isArray(value),
    "invalid_response",
    "The server returned an invalid list.",
  );
  return value.map((v) => text(v));
};
export const nullableText = (value: unknown) =>
  value === null ? null : text(value);
export const same = (a: unknown, b: unknown) => stable(a) === stable(b);
export function stable(value: unknown): string {
  return JSON.stringify(value, (_, item) =>
    item && typeof item === "object" && !Array.isArray(item)
      ? Object.fromEntries(
          Object.keys(item)
            .sort()
            .map((key) => [key, item[key]]),
        )
      : item,
  );
}
export const selected = (ids: string[]) => {
  ensure(
    ids.every(
      (id) =>
        typeof id === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/.test(id),
    ) && new Set(ids).size === ids.length,
    "invalid_input",
    "Selections must contain unique valid IDs.",
  );
  return [...ids].sort();
};
export interface Generation {
  id: string;
  status:
    | "queued"
    | "generating"
    | "validating"
    | "preview ready"
    | "failed"
    | "stale";
  mode: "create" | "edit";
  mutation: number;
  attempts: number;
  requestText: string;
  diagnostics: string;
  provider: string | null;
  model: string | null;
  nextAttemptAt: string;
  failureCategory: string | null;
}
export function generation(value: unknown): Generation | null {
  if (value === null || value === undefined) return null;
  const data = row(value);
  ensure(
    [
      "queued",
      "generating",
      "validating",
      "preview ready",
      "failed",
      "stale",
    ].includes(String(data.status)) &&
      ["create", "edit"].includes(String(data.mode)) &&
      typeof data.diagnostics === "string" &&
      data.diagnostics.length <= 16384 &&
      typeof data.requestText === "string" &&
      data.requestText.length <= 16384 &&
      count(data.attempts) <= 3 &&
      typeof data.nextAttemptAt === "string" &&
      Number.isFinite(Date.parse(data.nextAttemptAt)),
    "invalid_response",
    "The server returned an invalid generation job.",
  );
  return freezeValidated({
    id: text(data.id),
    status: data.status as Generation["status"],
    mode: data.mode as Generation["mode"],
    mutation: count(data.mutation),
    attempts: count(data.attempts),
    requestText: data.requestText,
    diagnostics: data.diagnostics,
    provider: nullableText(data.provider),
    model: nullableText(data.model),
    nextAttemptAt: data.nextAttemptAt,
    failureCategory: nullableText(data.failureCategory),
  });
}
export type FullManifest = RuntimeManifest & { generation: Generation | null };
export function manifest(value: unknown, appId: string): FullManifest {
  const input = row(runtimeJsonSnapshot(value));
  const decoded = decodeRuntimeManifest(input);
  ensure(
    decoded.id === appId,
    "invalid_response",
    "The response belongs to a different app.",
  );
  const editor =
    !decoded.archived &&
    ["owner", "builder"].includes(decoded.role) &&
    decoded.capabilities.editDefinition === true;
  return freezeValidated({
    ...decoded,
    draft: editor ? decoded.draft : null,
    generation: editor ? generation(input.generation) : null,
  });
}
export interface PlatformCapabilities {
  invalidations:
    import("../runtime/invalidationTypes").InvalidationCapability | null;
  generation: boolean;
  guidance: boolean;
  effects: string[];
  privateMedia: boolean;
}
export function platformCapabilities(value: unknown): PlatformCapabilities {
  const data = row(value);
  ensure(
    data.apiVersion === 1 &&
      Array.isArray(data.formatVersions) &&
      data.formatVersions.includes(1) &&
      typeof data.generation === "boolean" &&
      typeof data.guidance === "boolean" &&
      typeof data.privateMedia === "boolean",
    "invalid_response",
    "Platform capabilities could not be confirmed.",
  );
  let invalidations:
    import("../runtime/invalidationTypes").InvalidationCapability | null = null;
  if (data.invalidations !== undefined && data.invalidations !== null) {
    const capability = row(data.invalidations);
    ensure(
      capability.mode === "poll.v1" &&
        Number.isSafeInteger(capability.minimumIntervalMs) &&
        (capability.minimumIntervalMs as number) >= 15000 &&
        (capability.minimumIntervalMs as number) <= 120000,
      "invalid_response",
      "The current live refresh capability is unsupported.",
    );
    invalidations = {
      mode: "poll.v1",
      minimumIntervalMs: capability.minimumIntervalMs as number,
    };
  }
  const effects = strings(data.effects);
  ensure(
    effects.every((effect) =>
      ["notifyOwner", "notifyAssignee", "notifyActiveClaimants"].includes(
        effect,
      ),
    ),
    "invalid_response",
    "Unsupported effect capability.",
  );
  return freezeValidated({
    invalidations,
    generation: data.generation,
    guidance: data.guidance,
    effects,
    privateMedia: data.privateMedia,
  });
}
export interface PublicationReview {
  candidateHash: string;
  expectedRevision: number;
  baseVersionId: string | null;
  currentVersionId: string | null;
  reviewHash: string;
  changes: string[];
  compatibilityErrors: string[];
  enabledRuleIds: string[];
  activateExistingRecordIds: string[];
}
export function publicationReview(value: unknown): PublicationReview {
  const data = row(value);
  return freezeValidated({
    candidateHash: text(data.candidateHash),
    expectedRevision: count(data.expectedRevision),
    baseVersionId: nullableText(data.baseVersionId),
    currentVersionId: nullableText(data.currentVersionId),
    reviewHash: text(data.reviewHash),
    changes: strings(data.changes),
    compatibilityErrors: strings(data.compatibilityErrors),
    enabledRuleIds: selected(strings(data.enabledRuleIds)),
    activateExistingRecordIds: selected(
      strings(data.activateExistingRecordIds),
    ),
  });
}
