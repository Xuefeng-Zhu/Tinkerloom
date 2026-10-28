import { ensure } from "../runtime/errors";
import { runtimeJsonSnapshot } from "../runtime/json";
import { freezeValidated } from "../runtime/immutable";
import { normalizeTimestamp } from "../spec/values";
export const object = (input: unknown): Record<string, unknown> => {
  ensure(
    input !== null && typeof input === "object" && !Array.isArray(input),
    "invalid_response",
    "The notification response is invalid.",
  );
  return input as Record<string, unknown>;
};
export function keys(
  value: Record<string, unknown>,
  expected: readonly string[],
) {
  ensure(
    Object.keys(value).length === expected.length &&
      expected.every((key) => Object.hasOwn(value, key)),
    "invalid_response",
    "The notification response contains unsupported or missing fields.",
  );
}
export function id(value: unknown, semantic = false): string {
  ensure(
    typeof value === "string" &&
      (semantic
        ? /^[A-Za-z][A-Za-z0-9_]{0,63}$/
        : /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/
      ).test(value),
    "invalid_response",
    "The notification response contains an invalid identity.",
  );
  return value;
}
export const nullableId = (value: unknown, semantic = false) =>
  value === null ? null : id(value, semantic);
function text(value: unknown, max: number): string {
  ensure(
    typeof value === "string" && value.length <= max,
    "invalid_response",
    "The notification response contains invalid text.",
  );
  return value;
}
export function instant(value: unknown): string {
  ensure(
    typeof value === "string" && value.endsWith("Z"),
    "invalid_response",
    "The notification response contains an invalid UTC instant.",
  );
  normalizeTimestamp(value);
  return value;
}
export function integer(value: unknown, max = Number.MAX_SAFE_INTEGER): number {
  ensure(
    typeof value === "number" &&
      Number.isSafeInteger(value) &&
      value >= 0 &&
      value <= max,
    "invalid_response",
    "The notification response contains an invalid count.",
  );
  return value;
}
export interface InboxItem {
  id: string;
  appId: string;
  runId: string;
  recordId: string | null;
  collectionId: string | null;
  title: string;
  body: string;
  createdAt: string;
  isRead: boolean;
}
export interface InboxPage {
  items: InboxItem[];
  nextCursor: string | null;
}
export function inboxPage(input: unknown): InboxPage {
  const data = object(runtimeJsonSnapshot(input));
  keys(data, ["items", "nextCursor"]);
  ensure(
    Array.isArray(data.items) && data.items.length <= 100,
    "invalid_response",
    "The inbox page is invalid.",
  );
  const items = data.items.map((input) => {
    const v = object(input);
    keys(v, [
      "id",
      "appId",
      "runId",
      "recordId",
      "collectionId",
      "title",
      "body",
      "createdAt",
      "isRead",
    ]);
    ensure(
      typeof v.isRead === "boolean" &&
        (v.recordId === null) === (v.collectionId === null),
      "invalid_response",
      "The notification target is invalid.",
    );
    return {
      id: id(v.id),
      appId: id(v.appId),
      runId: id(v.runId),
      recordId: nullableId(v.recordId),
      collectionId: nullableId(v.collectionId, true),
      title: text(v.title, 4096),
      body: text(v.body, 16384),
      createdAt: instant(v.createdAt),
      isRead: v.isRead,
    };
  });
  const cursor = nullableId(data.nextCursor);
  ensure(
    new Set(items.map((v) => v.id)).size === items.length &&
      (cursor === null || cursor === items.at(-1)?.id),
    "invalid_response",
    "The inbox cursor or identities are invalid.",
  );
  return freezeValidated({ items, nextCursor: cursor });
}
export interface ReadNotification {
  op: "spec.readNotification";
  appId: string;
  runId: string;
  notificationId: string;
  operationId: string;
}
export function readCommand(input: unknown): ReadNotification {
  const data = object(runtimeJsonSnapshot(input));
  keys(data, ["op", "appId", "runId", "notificationId", "operationId"]);
  ensure(
    data.op === "spec.readNotification",
    "invalid_saved_command",
    "The retained request is not a notification read receipt. It has not been replaced.",
  );
  return freezeValidated({
    op: "spec.readNotification",
    appId: id(data.appId),
    runId: id(data.runId),
    notificationId: id(data.notificationId),
    operationId: id(data.operationId),
  });
}
export function readAcknowledgement(input: unknown, command: ReadNotification) {
  const data = object(runtimeJsonSnapshot(input));
  keys(data, ["notificationId", "isRead"]);
  ensure(
    data.notificationId === command.notificationId && data.isRead === true,
    "invalid_response",
    "The read receipt does not confirm the original notification.",
  );
}
export const runStatuses = [
  "pending",
  "succeeded",
  "suppressed",
  "failed",
] as const;
export interface AutomationRun {
  id: string;
  ruleId: string | null;
  recordId: string;
  status: (typeof runStatuses)[number];
  dueAt: string;
  nextAttemptAt: string;
  attempts: number;
  errorCategory: string | null;
  recipientCount: number;
}
export function runsPage(input: unknown): {
  runs: AutomationRun[];
  nextCursor: string | null;
} {
  const data = object(runtimeJsonSnapshot(input));
  keys(data, ["runs", "nextCursor"]);
  ensure(
    Array.isArray(data.runs) && data.runs.length <= 50,
    "invalid_response",
    "The run page is invalid.",
  );
  const runs = data.runs.map((input) => {
    const v = object(input);
    keys(v, [
      "id",
      "ruleId",
      "recordId",
      "status",
      "dueAt",
      "nextAttemptAt",
      "attempts",
      "errorCategory",
      "recipientCount",
    ]);
    ensure(
      runStatuses.includes(v.status as never) &&
        (v.errorCategory === null ||
          (typeof v.errorCategory === "string" &&
            /^[a-z0-9_]{1,96}$/.test(v.errorCategory))),
      "invalid_response",
      "The run status is invalid.",
    );
    return {
      id: id(v.id),
      ruleId: nullableId(v.ruleId, true),
      recordId: id(v.recordId),
      status: v.status as AutomationRun["status"],
      dueAt: instant(v.dueAt),
      nextAttemptAt: instant(v.nextAttemptAt),
      attempts: integer(v.attempts, 5),
      errorCategory: v.errorCategory as string | null,
      recipientCount: integer(v.recipientCount, 500),
    };
  });
  const cursor = nullableId(data.nextCursor);
  ensure(
    new Set(runs.map((v) => v.id)).size === runs.length &&
      (cursor === null || cursor === runs.at(-1)?.id),
    "invalid_response",
    "The run cursor or identities are invalid.",
  );
  return freezeValidated({ runs, nextCursor: cursor });
}
export const reminderStates = [
  "unset",
  "disabled",
  "unenrolled",
  "pending",
  "delivered",
  "suppressed",
  "failed",
] as const;
export interface RuleReminder {
  ruleId: string;
  state: (typeof reminderStates)[number];
  scheduledAt: string | null;
  eligible: boolean;
  recipientCount: number;
}
export function reminderPage(
  input: unknown,
  versionId: string,
  ruleIds: readonly string[],
): RuleReminder[] {
  const data = object(runtimeJsonSnapshot(input));
  keys(data, ["states", "versionId"]);
  ensure(
    data.versionId === versionId &&
      Array.isArray(data.states) &&
      data.states.length <= 10,
    "invalid_response",
    "Reminder status belongs to a different version or is invalid.",
  );
  const states = data.states.map((input) => {
    const v = object(input);
    keys(v, ["ruleId", "state", "scheduledAt", "eligible", "recipientCount"]);
    ensure(
      reminderStates.includes(v.state as never) &&
        typeof v.eligible === "boolean",
      "invalid_response",
      "The reminder status is invalid.",
    );
    const ruleId = id(v.ruleId, true);
    ensure(
      ruleIds.includes(ruleId),
      "invalid_response",
      "Reminder status belongs to an unknown rule.",
    );
    return {
      ruleId,
      state: v.state as RuleReminder["state"],
      scheduledAt: v.scheduledAt === null ? null : instant(v.scheduledAt),
      eligible: v.eligible,
      recipientCount: integer(v.recipientCount, 500),
    };
  });
  ensure(
    new Set(states.map((v) => v.ruleId)).size === states.length,
    "invalid_response",
    "Duplicate reminder rule status.",
  );
  return freezeValidated(states);
}
export interface SessionLifetime {
  readonly active: boolean;
  assertActive(): void;
  onDispose?(cleanup: () => void): () => void;
}
