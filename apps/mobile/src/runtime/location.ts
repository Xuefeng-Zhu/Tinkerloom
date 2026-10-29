import { ensure } from "./errors";
import type { RuntimeAdapter, RuntimeLocation, RuntimeRecord } from "./types";
import type { ViewSpec, ViewSpecOf } from "../spec/types";

export type RuntimeNavigationKind = "push" | "pop" | "external";
export interface RuntimeLocationRequest {
  pageId?: string;
  recordId?: string;
  editing?: boolean;
}
export const sameLocation = (a: RuntimeLocation, b: RuntimeLocation) =>
  a.pageId === b.pageId &&
  a.recordId === b.recordId &&
  !!a.editing === !!b.editing;

export function locationHistory(
  history: readonly RuntimeLocation[],
  current: RuntimeLocation,
  next: RuntimeLocation,
  kind: RuntimeNavigationKind,
  tabPageIds: readonly string[],
): RuntimeLocation[] {
  if (sameLocation(current, next)) return [...history];
  if (kind !== "push") {
    const index = history.findLastIndex((item) => sameLocation(item, next));
    return index < 0 ? [] : history.slice(0, index);
  }
  if (tabPageIds.includes(next.pageId) && !next.recordId && !next.editing)
    return [];
  return [...history, { ...current }];
}

export function viewsAt(adapter: RuntimeAdapter, pageId: string): ViewSpec[] {
  const nav = adapter.spec.navigation;
  return nav
    ? (nav.pages
        .find((page) => page.id === pageId)
        ?.viewIds.map((id) =>
          adapter.spec.views.find((view) => view.id === id)!,
        ) ?? [])
    : adapter.spec.views;
}

export function recordEditorView(
  adapter: RuntimeAdapter,
  location: RuntimeLocation,
  record: RuntimeRecord,
): ViewSpecOf<"form"> | null {
  const candidates = viewsAt(adapter, location.pageId).filter(
    (view) => view.collectionId === record.collectionId,
  );
  const editable = (view: ViewSpec) =>
    view.actionIds.some((id) => {
      const action = adapter.spec.actions.find((item) => item.id === id);
      return (
        action?.capability === "records.patch.v1" &&
        adapter.permits(action, record)
      );
    });
  const view =
    candidates.find((item) => item.type === "form" && editable(item)) ??
    candidates.find(editable);
  if (!view) return null;
  return view.type === "form"
    ? view
    : {
        id: `editor_${view.id}`,
        type: "form",
        label: "Edit record",
        collectionId: record.collectionId,
        actionIds: view.actionIds,
        ...(view.fieldIds ? { fieldIds: view.fieldIds } : {}),
      };
}

/** URL identities are resolved against the current manifest and an authorized get. */
export async function resolveLocation(
  adapter: RuntimeAdapter,
  request: RuntimeLocationRequest,
): Promise<RuntimeLocation> {
  const nav = adapter.spec.navigation;
  const entry = nav?.entryPageId ?? "__legacy__";
  let pageId = request.pageId ?? entry;
  ensure(
    nav ? nav.pages.some((page) => page.id === pageId) : pageId === entry,
    "invalid_location",
    "This page is unavailable in the current app version.",
  );
  ensure(
    !request.editing || !!request.recordId,
    "invalid_location",
    "Editing a record requires its identity.",
  );
  if (!request.recordId) return { pageId };
  const record = await adapter.get(request.recordId);
  ensure(
    record.id === request.recordId,
    "invalid_response",
    "The requested record did not match the response.",
  );
  if (!request.pageId && nav) {
    const view = adapter.spec.views.find(
      (item) =>
        item.collectionId === record.collectionId &&
        item.type === (request.editing ? "form" : "details") &&
        (!request.editing ||
          item.actionIds.some((id) => {
            const action = adapter.spec.actions.find(
              (candidate) => candidate.id === id,
            );
            return (
              action?.capability === "records.patch.v1" &&
              adapter.permits(action, record)
            );
          })),
    );
    const page =
      view && nav.pages.find((item) => item.viewIds.includes(view.id));
    if (page) pageId = page.id;
  }
  const location: RuntimeLocation = {
    pageId,
    recordId: record.id,
    ...(request.editing ? { editing: true } : {}),
  };
  ensure(
    viewsAt(adapter, pageId).some(
      (view) => view.collectionId === record.collectionId,
    ),
    "invalid_location",
    "This record is unavailable on the requested page.",
  );
  ensure(
    !request.editing || recordEditorView(adapter, location, record) !== null,
    "invalid_location",
    "Editing this record is unavailable with your current access.",
  );
  return location;
}
