type SaveKind = "record" | "draft" | "publish";

/** Pending stores the command while both in flight and awaiting recovery. */
export function savePresentation(kind: SaveKind | null, busy: boolean) {
  if (!kind) return null;
  const noun =
    kind === "record"
      ? "record save"
      : kind === "draft"
        ? "draft save"
        : "publication";
  return {
    title: busy
      ? kind === "record"
        ? "Saving record…"
        : kind === "draft"
          ? "Saving draft…"
          : "Publishing…"
      : `A ${noun} is unconfirmed`,
    description: busy
      ? "Waiting for the server to confirm this save."
      : "Its original input and version are retained. Retry checks the same operation; it does not start another save.",
    canRetry: !busy,
  };
}
