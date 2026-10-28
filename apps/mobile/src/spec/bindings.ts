import { requireSpec } from "./errors";
import type {
  ActionSpec,
  AppSpec,
  BehaviorSpec,
  CollectionSpec,
  DeviceCapability,
  DeviceInfoField,
  FieldSpec,
  PageSpec,
  ViewSpec,
  ViewType,
  ViewSpecOf,
} from "./types";

export const CONTENT_VIEW_TYPES = new Set<ViewType>([
  "richText",
  "banner",
  "clock",
  "timer",
  "deviceInfo",
  "deviceControl",
]);
export const RICH_VIEW_TYPES = new Set<ViewType>([
  "deviceInfo",
  "deviceControl",
  "clock",
  "timer",
  "table",
  "calendar",
  "timeline",
  "chart",
  "metric",
  "imageCards",
  "gallery",
  "richText",
  "banner",
  "checklist",
]);
function find<T extends { id: string }>(
  items: readonly T[],
  id: string,
  kind: string,
): T {
  const item = items.find((entry) => entry.id === id);
  requireSpec(item, id, `Unknown ${kind}`);
  return item;
}
export const getCollection = (spec: AppSpec, id: string): CollectionSpec =>
  find(spec.collections, id, "collection");
export const getField = (collection: CollectionSpec, id: string): FieldSpec =>
  find(collection.fields, id, "field");
export const getBehavior = (
  collection: CollectionSpec,
  id: string,
): BehaviorSpec => find(collection.behaviors, id, "behavior");
export const getAction = (spec: AppSpec, id: string): ActionSpec =>
  find(spec.actions, id, "action");
export const getView = (spec: AppSpec, id: string): ViewSpec =>
  find(spec.views, id, "view");
export const getPage = (spec: AppSpec, id: string): PageSpec =>
  find(spec.navigation?.pages ?? [], id, "page");
export function isViewType<K extends ViewType>(
  view: ViewSpec,
  type: K,
): view is ViewSpec & ViewSpecOf<K> {
  return view.type === type;
}
export const isContentView = (view: ViewSpec) =>
  CONTENT_VIEW_TYPES.has(view.type);
export function isConfiguredView(view: ViewSpec): boolean {
  return Boolean(
    Object.keys(view.options ?? {}).length ||
    view.presentation !== undefined ||
    view.fieldIds?.length ||
    view.filterFieldIds?.length ||
    view.query !== undefined ||
    view.dateFilter !== undefined ||
    view.detailPageId !== undefined ||
    view.formPageId !== undefined,
  );
}
export function collectionForView(
  spec: AppSpec,
  view: ViewSpec,
): CollectionSpec | null {
  return isContentView(view) ? null : getCollection(spec, view.collectionId!);
}
export function fieldsForView(spec: AppSpec, view: ViewSpec): FieldSpec[] {
  const collection = collectionForView(spec, view);
  return !collection
    ? []
    : view.fieldIds?.length
      ? view.fieldIds.map((id) => getField(collection, id))
      : [...collection.fields];
}
export function editableFieldsForView(
  spec: AppSpec,
  view: ViewSpec,
): FieldSpec[] {
  const collection = collectionForView(spec, view);
  const managed = new Set(
    collection?.behaviors
      .filter((behavior) => behavior.type === "workflow.v1")
      .map((behavior) => behavior.fieldId),
  );
  return fieldsForView(spec, view).filter((field) => !managed.has(field.id));
}
export const actionsForView = (spec: AppSpec, view: ViewSpec): ActionSpec[] =>
  view.actionIds.map((id) => getAction(spec, id));
export const viewsForPage = (spec: AppSpec, page: PageSpec): ViewSpec[] =>
  page.viewIds.map((id) => getView(spec, id));
export function deviceFieldCapability(
  field: DeviceInfoField,
): DeviceCapability {
  return field === "batteryLevel" || field === "charging"
    ? "battery"
    : field === "model" || field === "osVersion"
      ? "device"
      : field === "connection"
        ? "connection"
        : "locale";
}
export function requestedDeviceCapabilities(spec: AppSpec): DeviceCapability[] {
  return [
    ...new Set(
      spec.views.flatMap((view): DeviceCapability[] =>
        view.type === "deviceInfo"
          ? (view.options?.fields ?? []).map(deviceFieldCapability)
          : view.type === "deviceControl" && view.options
            ? [view.options.control]
            : [],
      ),
    ),
  ];
}
/** Interpret defaults for display; never write these back into a definition. */
export function clockOptions(view: ViewSpecOf<"clock">) {
  return {
    style: "digital",
    hourFormat: "system",
    showSeconds: false,
    showDate: true,
    ...view.options,
  } as const;
}
export function timerOptions(view: ViewSpecOf<"timer">) {
  return { durationMinutes: 25, ...view.options };
}
