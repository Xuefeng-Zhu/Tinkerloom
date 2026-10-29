import {
  observePreviewImages,
  snapshotPreviewImages,
  staticPreviewImageIds,
} from "./previewImageAssets";
import type { PreviewStaticImageAssets } from "./previewImageAssets";
import { ownValue } from "../spec/ownValue";
import {
  getAction,
  getBehavior,
  getCollection,
  getField,
} from "../spec/bindings";
import { decodeAppSpec } from "../spec/decode";
import { canonicalJson } from "../spec/schema";
import { runtimeJsonSnapshot } from "./json";
import {
  normalizeFieldValue,
  normalizeRecordValues,
  validateRecordQuery,
} from "../spec/values";
import type {
  ActionSpec,
  AggregateQuery,
  AppSpec,
  CollectionSpec,
  FieldSpec,
  JsonValue,
  RecordQuery,
  RecordValues,
} from "../spec/types";
import { ensure, unavailable } from "./errors";
import { policyPermits } from "./permissions";
import { freezeValidated } from "./immutable";
import { aggregateRecords, matchingRecords, queryIdentity } from "./query";
import type {
  CommandOutcome,
  ImageAsset,
  PickedImage,
  RecordPage,
  ReminderState,
  RuntimeAdapter,
  RuntimeCommand,
  RuntimeRecord,
  RuntimeRole,
  RuntimeSummary,
} from "./types";

const copy = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
const sampleImage =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==";
function sampleValue(
  field: FieldSpec,
  index: number,
): string | number | boolean {
  switch (field.type) {
    case "text":
      return field.id === "title"
        ? ["Community morning", "A small beginning", "Make room for good"][
            index % 3
          ]
        : `Example ${field.label.toLowerCase()}`;
    case "integer":
      return index + 1;
    case "number":
      return (index + 1) * 1.5;
    case "boolean":
      return index % 2 === 0;
    case "choice":
      return field.choices![index % field.choices!.length];
    case "timestamp":
      return new Date(Date.UTC(2030, 0, 5 + index, 10)).toISOString();
    case "member":
      return "preview_member";
    case "image":
      return `preview_image_${index % 3}`;
  }
}
/** The same synthetic examples as the Dart renderer; never reads a live adapter. */
export function syntheticRecords(
  collection: CollectionSpec,
  now = new Date(),
): RecordValues[] {
  const fields = collection.fields;
  if (
    collection.id === "tasks" &&
    fields.some((f) => f.id === "reminderAt") &&
    fields.some(
      (f) =>
        f.id === "status" &&
        f.choices?.includes("Open") &&
        f.choices.includes("Done"),
    )
  ) {
    const at = (day: number, hour: number) =>
      new Date(
        now.getFullYear(),
        now.getMonth(),
        now.getDate() + day,
        hour,
      ).toISOString();
    const examples: Record<string, unknown>[] = [
      {
        title: "Plan the day",
        status: "Done",
        priority: "Normal",
        notes: "Choose a few things that matter.",
        dueAt: at(0, 9),
      },
      {
        title: "Make time for a walk",
        status: "Open",
        priority: "High",
        notes: "A little fresh air.",
        dueAt: at(0, 17),
      },
      {
        title: "Yesterday's notes",
        status: "Open",
        priority: "Normal",
        dueAt: at(-1, 16),
      },
      { title: "An undated idea", status: "Open", priority: "Low" },
    ];
    return examples.map((example, i) =>
      normalizeRecordValues(
        collection,
        Object.fromEntries(
          fields.flatMap((f) => {
            if (Object.hasOwn(example, f.id)) {
              try {
                return [[f.id, normalizeFieldValue(f, example[f.id])]];
              } catch {
                return [[f.id, sampleValue(f, i)]];
              }
            }
            return f.required ? [[f.id, sampleValue(f, i)]] : [];
          }),
        ),
      ),
    );
  }
  const rich = ["projects", "memories", "checkins", "events"].includes(
    collection.id,
  );
  return Array.from(
    { length: rich ? (collection.id === "checkins" ? 14 : 6) : 3 },
    (_, i) =>
      normalizeRecordValues(
        collection,
        Object.fromEntries(
          fields.map((f) => {
            let value = sampleValue(f, i);
            if (rich && f.type === "timestamp")
              value = new Date(
                now.getFullYear(),
                now.getMonth(),
                now.getDate() + (collection.id === "projects" ? i - 1 : -i),
                10,
              ).toISOString();
            else if (
              rich &&
              f.type === "integer" &&
              ["rating", "energy"].includes(f.id)
            )
              value = (i % 5) + 1;
            else if (rich && f.type === "number" && f.id === "minutes")
              value = [20, 35, 45, 15, 60, 30, 25][i % 7];
            return [f.id, value];
          }),
        ),
      ),
  );
}
export interface PreviewOptions {
  role?: RuntimeRole;
  now?: Date;
  records?: Record<string, RecordValues[]>;
  staticImageAssets?: PreviewStaticImageAssets;
}
export class PreviewRuntimeAdapter implements RuntimeAdapter {
  readonly appId = "preview";
  readonly versionId = "preview_v1";
  readonly preview = true;
  readonly archived = false;
  private currentSpec: AppSpec;
  get spec(): AppSpec {
    return this.currentSpec;
  }
  readonly role: RuntimeRole;
  readonly approvedRuleIds: string[];
  readonly features = new Set([
    "members",
    "reminders",
    "imageRead",
    "watch",
  ] as const);
  private rows = new Map<string, RuntimeRecord>();
  private receipts = new Map<
    string,
    { request: string; outcome: CommandOutcome }
  >();
  private cursors = new Map<string, { query: string; anchor: string }>();
  private listeners = new Set<() => void>();
  private sequence = 0;
  private disposed = false;
  private staticImageAssets?: PreviewStaticImageAssets;
  private staticImages: ReadonlyMap<string, Readonly<ImageAsset>> = new Map();
  private stopImages = () => {};
  private imageEpoch = 0;
  get imageRevision() {
    return this.imageEpoch;
  }
  private replaceImages(spec: AppSpec, assets?: PreviewStaticImageAssets) {
    const images = snapshotPreviewImages(assets, staticPreviewImageIds(spec));
    this.stopImages();
    this.staticImageAssets = assets;
    this.staticImages = images;
    this.imageEpoch++;
    this.stopImages = observePreviewImages(assets, () => {
      this.staticImages = new Map();
      this.imageEpoch++;
      if (!this.disposed) for (const listener of this.listeners) listener();
    });
  }
  /** Preserve this isolated sandbox only when the declaration changes presentation. */
  applyPresentationSpec(
    input: AppSpec,
    staticImageAssets: PreviewStaticImageAssets | null = this
      .staticImageAssets ?? null,
  ) {
    const next = freezeValidated(decodeAppSpec(input));
    ensure(!this.disposed, "disposed", "The preview is closed.");
    ensure(
      presentationFingerprint(this.spec) === presentationFingerprint(next),
      "preview_behavior_changed",
      "This change requires a new isolated preview.",
    );
    this.replaceImages(next, staticImageAssets ?? undefined);
    this.currentSpec = next;
    for (const listener of this.listeners) listener();
  }
  constructor(spec: AppSpec, options: PreviewOptions = {}) {
    this.currentSpec = freezeValidated(decodeAppSpec(spec));
    this.replaceImages(this.currentSpec, options.staticImageAssets);
    this.role = options.role ?? "owner";
    this.approvedRuleIds = this.spec.automationRequests.map((rule) => rule.id);
    for (const c of this.spec.collections)
      for (const data of options.records?.[c.id] ??
        syntheticRecords(c, options.now)) {
        const id = `preview_record_${++this.sequence}`,
          capacity = c.behaviors.some((b) => b.type === "capacity.v1");
        this.rows.set(id, {
          id,
          collectionId: c.id,
          data: normalizeRecordValues(c, runtimeJsonSnapshot(data)),
          revision: 1,
          writtenUnderVersionId: this.versionId,
          capacity: capacity ? 4 : null,
          allocated: capacity ? 0 : null,
          claimed: false,
          allowedActions: this.spec.actions
            .filter((a) => a.collectionId === c.id)
            .map((a) => a.id),
        });
      }
  }
  private active() {
    ensure(!this.disposed, "disposed", "This preview is closed.");
  }
  permits(action: ActionSpec, record?: RuntimeRecord) {
    return policyPermits(this.spec, this.role, this.archived, action, record);
  }
  async query(collectionId: string, input: RecordQuery): Promise<RecordPage> {
    this.active();
    const c = getCollection(this.spec, collectionId),
      query = validateRecordQuery(c, runtimeJsonSnapshot(input) as RecordQuery),
      rows = matchingRecords(c, [...this.rows.values()], query),
      identity = queryIdentity(c.id, query);
    let offset = 0;
    if (query.cursor) {
      const cursor = this.cursors.get(query.cursor);
      ensure(
        cursor && cursor.query === identity,
        "invalid_cursor",
        "The cursor belongs to another query.",
      );
      const index = rows.findIndex((r) => r.id === cursor.anchor);
      ensure(
        index >= 0,
        "revision_conflict",
        "The page anchor changed. Refresh the view.",
      );
      offset = index + 1;
    }
    const page = rows.slice(offset, offset + query.limit!);
    let nextCursor: string | null = null;
    if (offset + page.length < rows.length) {
      nextCursor = `preview_cursor_${++this.sequence}`;
      this.cursors.set(nextCursor, {
        query: identity,
        anchor: page.at(-1)!.id,
      });
    }
    return copy({
      records: page,
      total: rows.length,
      nextCursor,
      versionId: this.versionId,
    });
  }
  async get(recordId: string) {
    this.active();
    const row = this.rows.get(recordId);
    ensure(row, "not_found", "The record is no longer available.");
    return copy(row);
  }
  async summary(
    collectionId: string,
    input: RecordQuery,
    groupFieldId: string,
  ): Promise<RuntimeSummary> {
    this.active();
    const c = getCollection(this.spec, collectionId),
      f = getField(c, groupFieldId);
    ensure(
      f.type === "choice",
      "invalid_query",
      "Summary groups need a choice field.",
    );
    const rows = matchingRecords(c, [...this.rows.values()], input);
    return {
      total: rows.length,
      groups: Object.fromEntries(
        f.choices!.map((choice) => [
          choice,
          rows.filter((r) => ownValue(r.data, f.id) === choice).length,
        ]),
      ),
      versionId: this.versionId,
    };
  }
  async aggregate(
    collectionId: string,
    query: RecordQuery,
    aggregate: AggregateQuery,
  ) {
    this.active();
    return aggregateRecords(
      getCollection(this.spec, collectionId),
      [...this.rows.values()],
      query,
      aggregate,
      this.versionId,
    );
  }
  async execute(input: RuntimeCommand): Promise<CommandOutcome> {
    this.active();
    const command = runtimeJsonSnapshot(input) as unknown as RuntimeCommand;
    ensure(
      command.appId === this.appId && command.versionId === this.versionId,
      "definition_conflict",
      "This command belongs to another runtime version.",
    );
    ensure(
      typeof command.operationId === "string" &&
        command.operationId.length > 0 &&
        command.operationId.length <= 128,
      "invalid_input",
      "Use a stable operation ID.",
    );
    const action = getAction(this.spec, command.actionId),
      c = getCollection(this.spec, action.collectionId),
      row = command.targetRecordId
        ? this.rows.get(command.targetRecordId)
        : undefined;
    ensure(
      this.permits(action, row),
      "forbidden",
      "You cannot perform this action.",
    );
    const request = canonicalJson(command),
      prior = this.receipts.get(command.operationId);
    if (prior) {
      ensure(
        prior.request === request,
        "operation_conflict",
        "That operation ID was already used with different input.",
      );
      return copy(prior.outcome);
    }
    const data = command.input;
    const keys = (allowed: string[]) =>
      ensure(
        Object.keys(data).every((k) => allowed.includes(k)),
        "invalid_input",
        "The command contains an unsupported input.",
      );
    const capacity = (value: JsonValue | undefined) => {
      ensure(
        typeof value === "number" &&
          Number.isInteger(value) &&
          value >= 0 &&
          value <= 10000,
        "invalid_input",
        "Capacity must be between 0 and 10,000.",
      );
      return value;
    };
    let updated: RuntimeRecord;
    if (action.capability === "records.create.v1") {
      ensure(
        command.targetRecordId === undefined &&
          command.expectedRecordRevision === undefined,
        "invalid_input",
        "Create actions allocate a new record.",
      );
      keys(["data", "capacity"]);
      ensure(
        data.data !== null &&
          typeof data.data === "object" &&
          !Array.isArray(data.data),
        "invalid_input",
        "Create needs record data.",
      );
      const values = { ...data.data } as Record<string, unknown>;
      for (const behavior of c.behaviors)
        if (behavior.type === "workflow.v1")
          ensure(
            ownValue(values, behavior.fieldId!) ===
              getField(c, behavior.fieldId!).choices![0],
            "invalid_input",
            "New records must start in the initial workflow state.",
          );
      for (const field of c.fields)
        if (
          field.type === "member" &&
          ownValue(values, field.id) !== undefined &&
          ownValue(values, field.id) !== null
        )
          ensure(
            ownValue(values, field.id) === "preview_member",
            "invalid_input",
            "Choose an eligible preview member.",
          );
      const hasCapacity = c.behaviors.some((b) => b.type === "capacity.v1");
      ensure(
        hasCapacity || data.capacity === undefined,
        "invalid_input",
        "This collection has no capacity.",
      );
      const id = `preview_record_${++this.sequence}`;
      updated = {
        id,
        collectionId: c.id,
        data: normalizeRecordValues(c, values),
        revision: 1,
        writtenUnderVersionId: this.versionId,
        capacity: hasCapacity ? capacity(data.capacity) : null,
        allocated: hasCapacity ? 0 : null,
        claimed: false,
        allowedActions: this.spec.actions
          .filter((a) => a.collectionId === c.id)
          .map((a) => a.id),
      };
    } else {
      ensure(
        row && row.collectionId === c.id,
        "not_found",
        "The record is no longer available.",
      );
      const capacityAction = action.capability.startsWith("capacity.");
      ensure(
        capacityAction || command.expectedRecordRevision === row.revision,
        "revision_conflict",
        "The record changed. Review it before trying a new command.",
      );
      updated = copy(row);
      ensure(
        Number.isSafeInteger(row.revision + 1),
        "revision_exhausted",
        "This record cannot accept another revision.",
      );
      switch (action.capability) {
        case "records.patch.v1": {
          keys(["data"]);
          ensure(
            data.data !== null &&
              typeof data.data === "object" &&
              !Array.isArray(data.data),
            "invalid_input",
            "Patch needs record data.",
          );
          const managed = new Set(
            c.behaviors.map((b) => b.fieldId).filter(Boolean),
          );
          ensure(
            Object.keys(data.data).every((key) => !managed.has(key)),
            "invalid_input",
            "Use the dedicated assignment or workflow action.",
          );
          updated.data = normalizeRecordValues(c, {
            ...row.data,
            ...data.data,
          });
          break;
        }
        case "assignment.assign.v1": {
          keys(["value"]);
          const behavior = getBehavior(c, action.behaviorId!);
          ensure(
            data.value === "preview_member" || data.value === null,
            "invalid_input",
            "Choose an eligible member.",
          );
          const value = normalizeFieldValue(
            getField(c, behavior.fieldId!),
            data.value,
          );
          if (value === null) delete updated.data[behavior.fieldId!];
          else updated.data[behavior.fieldId!] = value;
          break;
        }
        case "workflow.transition.v1": {
          keys(["value"]);
          const behavior = getBehavior(c, action.behaviorId!),
            current = String(ownValue(row.data, behavior.fieldId!));
          ensure(
            typeof data.value === "string" &&
              behavior.transitions?.[current]?.includes(data.value),
            "invalid_transition",
            "That workflow transition is not allowed.",
          );
          updated.data[behavior.fieldId!] = data.value;
          break;
        }
        case "capacity.configure.v1":
          keys(["capacity"]);
          ensure(
            row.allocated !== null,
            "invalid_input",
            "This record has no capacity pool.",
          );
          updated.capacity = capacity(data.capacity);
          ensure(
            updated.capacity >= row.allocated,
            "invalid_input",
            "Capacity cannot be less than current sign-ups.",
          );
          break;
        case "capacity.claim.v1":
          keys([]);
          ensure(
            row.capacity !== null && row.allocated !== null,
            "invalid_input",
            "Capacity is not configured.",
          );
          if (!row.claimed) {
            ensure(
              row.allocated < row.capacity,
              "exhausted_capacity",
              "This resource is full.",
            );
            updated.claimed = true;
            updated.allocated = row.allocated + 1;
          }
          break;
        case "capacity.release.v1":
          keys([]);
          ensure(
            row.allocated !== null,
            "invalid_input",
            "Capacity is not configured.",
          );
          if (row.claimed) {
            updated.claimed = false;
            updated.allocated = row.allocated - 1;
          }
          break;
      }
      if (!capacityAction) {
        updated.revision++;
        updated.writtenUnderVersionId = this.versionId;
      }
    }
    const outcome = {
      recordId: updated.id,
      revision: updated.revision,
      message: "Saved",
    };
    for (const field of c.fields)
      if (
        field.type === "member" &&
        ownValue(updated.data, field.id) !== undefined &&
        ownValue(updated.data, field.id) !== ownValue(row?.data, field.id)
      )
        ensure(
          ownValue(updated.data, field.id) === "preview_member",
          "invalid_input",
          "Choose an eligible preview member.",
        );
    this.rows.set(updated.id, updated);
    this.receipts.set(command.operationId, { request, outcome });
    queueMicrotask(() => {
      if (!this.disposed) for (const listener of this.listeners) listener();
    });
    return copy(outcome);
  }
  async members() {
    this.active();
    return [{ id: "preview_member", label: "Example member (preview)" }];
  }
  async reminderState(recordId: string): Promise<ReminderState> {
    const row = await this.get(recordId);
    const matching = this.spec.automationRequests.some(
      (rule) =>
        rule.trigger.collectionId === row.collectionId &&
        ownValue(row.data, rule.trigger.fieldId) !== undefined,
    );
    return {
      kind: matching ? "scheduled" : "none",
      label: matching
        ? "Example scheduled reminder (preview only)"
        : "No example reminder",
      synthetic: true,
    };
  }
  async readImage(assetId: string): Promise<ImageAsset> {
    this.active();
    const owned = this.staticImages.get(assetId);
    if (owned) return { ...owned };
    ensure(
      /^preview_image_\d+$/.test(assetId),
      "not_found",
      "This example image is unavailable.",
    );
    return {
      uri: sampleImage,
      width: 1,
      height: 1,
      alt: "Synthetic preview image",
    };
  }
  async pickImage(): Promise<PickedImage | null> {
    return unavailable(
      "Native image picking in an isolated preview. Use an example image instead",
    );
  }
  async uploadImage(_image: PickedImage): Promise<string> {
    this.active();
    return unavailable(
      "Byte uploads in an isolated preview. Use an example image or host-authorized static image instead",
    );
  }
  watch(listener: () => void) {
    this.active();
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }
  dispose() {
    this.disposed = true;
    this.stopImages();
    this.staticImages = new Map();
    this.staticImageAssets = undefined;
    this.listeners.clear();
    this.rows.clear();
    this.receipts.clear();
    this.cursors.clear();
  }
}

/** Original preview presentation guard; semantic bindings and queries remain fixed. */
export function presentationFingerprint(spec: AppSpec): string {
  const value = JSON.parse(canonicalJson(spec));
  delete value.name;
  delete value.theme;
  delete value.icon;
  delete value.appearance;
  value.collections = value.collections.map((c: Record<string, unknown>) => ({
    ...c,
    label: "",
    fields: (c.fields as Record<string, unknown>[]).map((f) => ({
      ...f,
      label: "",
    })),
  }));
  const keys: Record<string, string[]> = {
    clock: ["style", "hourFormat", "showSeconds", "showDate"],
    timer: ["durationMinutes"],
    chart: ["style"],
    metric: ["target"],
    richText: ["markdown"],
    banner: [
      "title",
      "body",
      "imageAssetId",
      "imageAlt",
      "tone",
      "imagePlacement",
    ],
    form: ["controls", "steps"],
  };
  value.views = value.views
    .map((v: Record<string, unknown>) => {
      const options = { ...((v.options as object) ?? {}) } as Record<
        string,
        unknown
      >;
      for (const key of keys[String(v.type)] ?? []) delete options[key];
      return { ...v, label: "", presentation: null, options };
    })
    .sort((a: { id: string }, b: { id: string }) => a.id.localeCompare(b.id));
  if (value.navigation)
    value.navigation.pages = value.navigation.pages.map(
      (p: Record<string, unknown>) => ({
        ...p,
        title: "",
        showDate: false,
        layout: null,
        viewIds: [...(p.viewIds as string[])].sort(),
      }),
    );
  value.requires = value.requires.filter(
    (cap: string) =>
      ![
        "views.configured.v1",
        "views.interactive.v1",
        "appearance.v1",
        "navigation.layouts.v1",
      ].includes(cap),
  );
  return canonicalJson(value);
}
