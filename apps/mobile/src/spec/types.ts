/** Full AppSpec v1 types. This domain does not imply renderer/handler support. */
export const FIELD_TYPES = [
  "text",
  "integer",
  "number",
  "boolean",
  "choice",
  "timestamp",
  "member",
  "image",
] as const;
export type FieldType = (typeof FIELD_TYPES)[number];
export const ACTION_CAPABILITIES = [
  "records.create.v1",
  "records.patch.v1",
  "assignment.assign.v1",
  "workflow.transition.v1",
  "capacity.configure.v1",
  "capacity.claim.v1",
  "capacity.release.v1",
] as const;
export type ActionCapability = (typeof ACTION_CAPABILITIES)[number];
export const VIEW_TYPES = [
  "list",
  "form",
  "details",
  "board",
  "summary",
  "capacity",
  "action",
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
] as const;
export type ViewType = (typeof VIEW_TYPES)[number];
export const POLICY_PRESETS = [
  "personalTracker.v1",
  "groupWorkflow.v1",
  "groupCapacitySignup.v1",
] as const;
export type PolicyPreset = (typeof POLICY_PRESETS)[number];
export const CAPABILITIES = [
  "collections.v1",
  ...VIEW_TYPES.map((type) => `views.${type}.v1` as const),
  "fields.image.v1",
  "views.interactive.v1",
  "capacity.v1",
  "workflow.v1",
  "assignment.v1",
  "notifications.inApp.v1",
  "navigation.v1",
  "appearance.v1",
  "navigation.layouts.v1",
  "views.configured.v1",
  "notifications.owner.v1",
  "automations.conditions.v1",
  ...ACTION_CAPABILITIES,
] as const;
export type Capability = (typeof CAPABILITIES)[number];
export const LIMITS = {
  definitionBytes: 131072,
  depth: 12,
  collections: 8,
  fields: 40,
  views: 16,
  actions: 32,
  rules: 10,
  pageSize: 100,
  filters: 8,
  aggregateBuckets: 366,
} as const;
export type JsonPrimitive = string | number | boolean | null;
export type JsonValue =
  JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type RecordValue = Exclude<JsonPrimitive, null>;
export type RecordValues = Record<string, RecordValue>;
export interface FieldSpec {
  id: string;
  label: string;
  type: FieldType;
  required: boolean;
  choices?: string[];
}
export type BehaviorType = "capacity.v1" | "workflow.v1" | "assignment.v1";
export interface BehaviorSpec {
  id: string;
  type: BehaviorType;
  fieldId?: string;
  transitions?: Record<string, string[]>;
}
export interface CollectionSpec {
  id: string;
  label: string;
  fields: FieldSpec[];
  behaviors: BehaviorSpec[];
}
export interface ActionSpec {
  id: string;
  label: string;
  capability: ActionCapability;
  collectionId: string;
  behaviorId?: string;
}
export type QueryOperator = "eq" | "in" | "gte" | "lte" | "lt" | "contains";
export interface QueryFilter {
  fieldId: string;
  operator: QueryOperator;
  value: JsonValue;
}
export interface QuerySort {
  fieldId: string;
  descending: boolean;
}
export interface ViewQuery {
  filters?: QueryFilter[];
  sort?: QuerySort[];
  limit?: number;
}
export interface RecordQuery extends ViewQuery {
  cursor?: string;
}
export interface DateFilterSpec {
  fieldId: string;
  period: "today" | "overdue";
}
export type NavigationIcon =
  "book" | "board" | "people" | "spark" | "check" | "today" | "list" | "chart";
export type PageLayout = "stacked" | "twoColumn" | "featuredFirst";
export interface PageSpec {
  id: string;
  title: string;
  viewIds: string[];
  showDate?: true;
  primaryActionId?: string;
  layout?: PageLayout;
}
export interface TabSpec {
  pageId: string;
  label: string;
  icon: NavigationIcon;
}
export interface NavigationSpec {
  entryPageId: string;
  pages: PageSpec[];
  tabs: TabSpec[];
}
export interface AppearanceSpec {
  style: "clean" | "editorial" | "playful";
  accentColor?: string;
  typography?: "sans" | "serif";
  density?: "compact" | "comfortable" | "spacious";
  corners?: "square" | "soft" | "rounded";
}
export type FormControlType =
  | "text"
  | "multiline"
  | "switch"
  | "checkbox"
  | "select"
  | "segmented"
  | "slider"
  | "stepper"
  | "rating"
  | "dateTime"
  | "imageUpload";
export interface FormControl {
  fieldId: string;
  control: FormControlType;
  hint?: string;
  min?: number;
  max?: number;
  step?: number;
}
export interface FormStep {
  id: string;
  title: string;
  fieldIds: string[];
}
export type Metric = "count" | "sum" | "average";
export type DeviceInfoField =
  | "batteryLevel"
  | "charging"
  | "model"
  | "osVersion"
  | "connection"
  | "language"
  | "region"
  | "timeZone";
export type DeviceControl =
  "flashlight" | "brightness" | "keepAwake" | "haptics";
export type DeviceCapability =
  "battery" | "device" | "connection" | "locale" | DeviceControl;
export interface ViewOptionsMap {
  list: Record<string, never>;
  details: Record<string, never>;
  summary: Record<string, never>;
  capacity: Record<string, never>;
  action: Record<string, never>;
  table: Record<string, never>;
  form: { controls?: FormControl[]; steps?: FormStep[] };
  board: { draggable?: true; moveActionId?: string };
  calendar: { dateFieldId: string };
  timeline: { dateFieldId: string };
  chart: {
    style: "bar" | "donut" | "line";
    metric: Metric;
    valueFieldId?: string;
    dateFieldId?: string;
    bucket?: "day" | "week" | "month";
    periods?: number;
  };
  metric: { metric: Metric; valueFieldId?: string; target?: number };
  imageCards: { imageFieldId: string; captionFieldId?: string };
  gallery: { imageFieldId: string; captionFieldId?: string };
  richText: { markdown: string };
  banner: {
    title: string;
    body?: string;
    imageAssetId?: string;
    imageAlt?: string;
    tone?: "neutral" | "accent" | "info" | "success" | "warning";
    imagePlacement?: "above" | "beside";
    targetPageId?: string;
  };
  checklist: {
    fieldId: string;
    actionId: string;
    checkedValue?: string;
    uncheckedValue?: string;
  };
  clock: {
    style?: "digital" | "analog";
    hourFormat?: "system" | "12" | "24";
    showSeconds?: boolean;
    showDate?: boolean;
  };
  timer: { durationMinutes?: number };
  deviceInfo: { fields: DeviceInfoField[] };
  deviceControl: { control: DeviceControl };
}
export type ContentViewType =
  "richText" | "banner" | "clock" | "timer" | "deviceInfo" | "deviceControl";
interface ViewBase<K extends ViewType> {
  id: string;
  type: K;
  label: string;
  actionIds: string[];
  titleFieldId?: string;
  groupByFieldId?: string;
  presentation?: "compact" | "cards";
  fieldIds?: string[];
  filterFieldIds?: string[];
  query?: ViewQuery;
  dateFilter?: DateFilterSpec;
  detailPageId?: string;
  formPageId?: string;
  options?: ViewOptionsMap[K];
}
export type ViewSpecOf<K extends ViewType> = ViewBase<K> &
  (K extends ContentViewType
    ? { collectionId?: never }
    : { collectionId: string });
export type ViewSpec = { [K in ViewType]: ViewSpecOf<K> }[ViewType];
export interface AutomationSpec {
  id: string;
  trigger: {
    type: "beforeTimestamp";
    collectionId: string;
    fieldId: string;
    offsetSeconds: number;
  };
  effect: {
    type: "notifyActiveClaimants" | "notifyAssignee" | "notifyOwner";
    channel: "inApp";
  };
  condition?: { fieldId: string; value: string };
}
export interface AppSpec {
  formatVersion: 1;
  name: string;
  theme: "teal" | "amber" | "blue" | "rose" | "sage";
  icon: "book" | "board" | "people" | "spark" | "check";
  requires: Capability[];
  collections: CollectionSpec[];
  views: ViewSpec[];
  actions: ActionSpec[];
  policyPresetRequest: PolicyPreset;
  automationRequests: AutomationSpec[];
  navigation?: NavigationSpec;
  appearance?: AppearanceSpec;
}
export interface AggregateQuery {
  metric: Metric;
  fieldId?: string;
  groupFieldId?: string;
  dateFieldId?: string;
  buckets?: { key: string; start: string; end: string }[];
}
