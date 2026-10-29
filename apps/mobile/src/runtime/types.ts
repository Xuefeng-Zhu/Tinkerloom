import type {
  ActionSpec,
  AggregateQuery,
  AppSpec,
  DeviceCapability,
  DeviceControl,
  DeviceInfoField,
  JsonValue,
  RecordQuery,
  RecordValues,
} from "../spec/types";

export type RuntimeRole = "owner" | "builder" | "member" | "viewer";
export interface RuntimeRecord {
  id: string;
  collectionId: string;
  data: RecordValues;
  revision: number;
  writtenUnderVersionId: string;
  capacity: number | null;
  allocated: number | null;
  claimed: boolean;
  allowedActions: string[];
}
export interface RecordPage {
  records: RuntimeRecord[];
  total: number;
  nextCursor: string | null;
  versionId: string;
}
export interface RuntimeSummary {
  total: number;
  groups: Record<string, number>;
  versionId: string;
}
export interface RuntimeAggregate {
  total: number;
  value: number | null;
  groups: { key: string; count: number; value: number | null }[];
  versionId: string;
}
export interface RuntimeMember {
  id: string;
  label: string;
}
export interface CommandOutcome {
  recordId: string;
  revision: number;
  message: string;
}
/** Immutable identity and input are retained together until an outcome is known. */
export interface RuntimeCommand {
  appId: string;
  operationId: string;
  versionId: string;
  actionId: string;
  targetRecordId?: string;
  expectedRecordRevision?: number;
  input: { [key: string]: JsonValue };
}
export interface RuntimeLocation {
  pageId: string;
  recordId?: string;
  editing?: boolean;
}
export interface ImageAsset {
  uri: string;
  width?: number;
  height?: number;
  alt?: string;
}
export interface PickedImage {
  bytes: Uint8Array;
  mimeType: "image/jpeg" | "image/png" | "image/webp";
  name: string;
}
export interface RuntimeImageUploadContext {
  versionId: string;
  actionId: string;
  fieldId: string;
  targetRecordId?: string;
  expectedRecordRevision?: number;
}
export interface ReminderState {
  kind: "pending" | "scheduled" | "delivered" | "cancelled" | "none";
  label: string;
  synthetic?: true;
}
export type DeviceState = Partial<
  Record<DeviceInfoField, string | number | boolean | null>
>;
export interface DeviceBridge {
  readonly available: readonly DeviceCapability[];
  read(fields: readonly DeviceInfoField[]): Promise<DeviceState>;
  control(control: DeviceControl, value?: boolean | number): Promise<void>;
  /** Restore the host's prior value/release its lease when a control view leaves. */
  release(control: DeviceControl): Promise<void>;
  dispose(): void;
}
/** Internal dispatch fence; never serialized into an Appwrite request. */
export interface RuntimeReadContext {
  isCurrent(): boolean;
}
export interface RuntimeAdapter {
  readonly appId: string;
  readonly versionId: string;
  readonly spec: AppSpec;
  readonly preview: boolean;
  readonly role: RuntimeRole;
  readonly archived: boolean;
  readonly approvedRuleIds: readonly string[];
  /** Feature names are implemented paths, not AppSpec vocabulary support. */
  readonly features: ReadonlySet<
    "members" | "reminders" | "imageRead" | "imageUpload" | "watch"
  >;
  query(
    collectionId: string,
    query: RecordQuery,
    context?: RuntimeReadContext,
  ): Promise<RecordPage>;
  get(recordId: string, context?: RuntimeReadContext): Promise<RuntimeRecord>;
  summary(
    collectionId: string,
    query: RecordQuery,
    groupFieldId: string,
    context?: RuntimeReadContext,
  ): Promise<RuntimeSummary>;
  aggregate(
    collectionId: string,
    query: RecordQuery,
    aggregate: AggregateQuery,
    context?: RuntimeReadContext,
  ): Promise<RuntimeAggregate>;
  execute(command: RuntimeCommand): Promise<CommandOutcome>;
  permits(action: ActionSpec, record?: RuntimeRecord): boolean;
  members(): Promise<RuntimeMember[]>;
  reminderState(recordId: string): Promise<ReminderState>;
  readImage(assetId: string): Promise<ImageAsset>;
  pickImage(): Promise<PickedImage | null>;
  uploadImage(
    image: PickedImage,
    context?: RuntimeImageUploadContext,
  ): Promise<string>;
  /** Pause active transport and controls when this runtime leaves the foreground. */
  setActive?(active: boolean): void;
  watch(listener: () => void): () => void;
  dispose(): void;
}
export type RuntimeTransport = (
  request: Record<string, unknown>,
  context?: RuntimeReadContext,
) => Promise<unknown>;
