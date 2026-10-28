import { ensure } from "./errors";
import { runtimeJsonSnapshot } from "./json";
import { freezeValidated } from "./immutable";
import type { RuntimeRole } from "./types";
export interface InvalidationStamp {
  appId: string;
  versionId: string | null;
  controlRevision: number;
  role: RuntimeRole;
  archived: boolean;
}
export interface InvalidationCapability {
  mode: "poll.v1";
  minimumIntervalMs: number;
}
export interface WatchActivitySnapshot {
  foreground: boolean;
  online: boolean;
}
export interface WatchActivity {
  getSnapshot(): WatchActivitySnapshot;
  subscribe(listener: () => void): () => void;
  dispose?(): void;
}
export interface WatchClock {
  setTimeout(callback: () => void, milliseconds: number): unknown;
  clearTimeout(handle: unknown): void;
}
export function decodeInvalidation(
  input: unknown,
  appId: string,
): InvalidationStamp {
  const data = runtimeJsonSnapshot(input) as Record<string, unknown>;
  ensure(
    data !== null &&
      typeof data === "object" &&
      !Array.isArray(data) &&
      Object.keys(data).length === 5 &&
      ["appId", "versionId", "controlRevision", "role", "archived"].every(
        (key) => Object.hasOwn(data, key),
      ),
    "invalid_response",
    "The app invalidation response is malformed.",
  );
  ensure(
    data.appId === appId &&
      (data.versionId === null ||
        (typeof data.versionId === "string" &&
          /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(data.versionId))) &&
      Number.isSafeInteger(data.controlRevision) &&
      (data.controlRevision as number) >= 0 &&
      ["owner", "builder", "member", "viewer"].includes(String(data.role)) &&
      typeof data.archived === "boolean",
    "invalid_response",
    "App invalidation identity or current authority could not be confirmed.",
  );
  return freezeValidated(data as unknown as InvalidationStamp);
}
export const invalidationIdentity = (stamp: InvalidationStamp) =>
  JSON.stringify([
    stamp.appId,
    stamp.versionId,
    stamp.controlRevision,
    stamp.role,
    stamp.archived,
  ]);
