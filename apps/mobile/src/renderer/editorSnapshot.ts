import type { RuntimeRecord } from "../runtime/types";

/** A pristine editor follows authorized refreshes. Local edits and retained commands keep their captured revision. */
export function editorRecordSnapshot(
  captured: RuntimeRecord | undefined,
  current: RuntimeRecord | null,
  dirty: boolean,
  pending: boolean,
): RuntimeRecord | undefined | null {
  if (!captured) return undefined;
  if (dirty || pending) return captured;
  return current?.id === captured.id &&
    current.collectionId === captured.collectionId
    ? current
    : null;
}
