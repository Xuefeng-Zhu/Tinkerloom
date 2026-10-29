import { ensure } from "../runtime/errors";
import { freezeValidated } from "../runtime/immutable";
import { runtimeJsonSnapshot } from "../runtime/json";
import { normalizeTimestamp } from "../spec/values";

export interface ActivityEntry {
  id: string;
  action: string;
  createdAt: string;
  status: "committed";
}
export interface ActivityPage {
  appId: string;
  items: readonly ActivityEntry[];
  nextCursor: string | null;
}
export function activityLabel(action: string): string {
  const labels: Readonly<Record<string, string>> = {
    "spec.createApp": "App created",
    "spec.instantiate": "App created from a starter",
    "spec.remix": "App structure remixed",
    "spec.saveDraft": "Private candidate saved",
    "spec.publish": "Version published",
    "records.create.v1": "Record created",
    "records.patch.v1": "Record edited",
    "assignment.assign.v1": "Assignment changed",
    "workflow.transition.v1": "Workflow changed",
    "capacity.configure.v1": "Capacity updated",
    "capacity.claim.v1": "Place claimed",
    "capacity.release.v1": "Place released",
    createInvitation: "Invitation created",
    revokeInvitation: "Invitation revoked",
    setGrant: "App access updated",
    join: "Invitation accepted",
    archiveApp: "App archived",
    "notification.read": "Reminder marked read",
    "media.ready": "Private image prepared",
  };
  return Object.hasOwn(labels, action) ? labels[action] : "App change";
}
export function activityId(value: unknown): string {
  ensure(
    typeof value === "string" &&
      /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(value),
    "invalid_response",
    "Activity contains an invalid identity.",
  );
  return value;
}
function object(value: unknown, expected: readonly string[]) {
  ensure(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "invalid_response",
    "Activity could not be read.",
  );
  const row = value as Record<string, unknown>;
  ensure(
    Object.keys(row).length === expected.length &&
      expected.every((key) => Object.hasOwn(row, key)),
    "invalid_response",
    "Activity contains unsupported or missing fields.",
  );
  return row;
}
export function activityPage(
  input: unknown,
  appId: string,
  limit = 50,
): ActivityPage {
  const data = object(runtimeJsonSnapshot(input), [
    "appId",
    "items",
    "nextCursor",
  ]);
  ensure(
    data.appId === appId &&
      Array.isArray(data.items) &&
      data.items.length <= limit &&
      (data.nextCursor === null ||
        (typeof data.nextCursor === "string" &&
          /^[A-Za-z0-9_-]+={0,2}$/.test(data.nextCursor) &&
          data.nextCursor.length <= 1024 &&
          data.items.length === limit)),
    "invalid_response",
    "The activity page does not match this app.",
  );
  const items = data.items.map((item) => {
    const row = object(item, ["id", "action", "createdAt", "status"]);
    ensure(
      typeof row.action === "string" &&
        /^[A-Za-z][A-Za-z0-9._-]{0,127}$/.test(row.action) &&
        typeof row.createdAt === "string" &&
        row.createdAt.length <= 64 &&
        normalizeTimestamp(row.createdAt) === row.createdAt &&
        row.status === "committed",
      "invalid_response",
      "Activity contains invalid committed metadata.",
    );
    return {
      id: activityId(row.id),
      action: row.action,
      createdAt: row.createdAt,
      status: row.status,
    } as ActivityEntry;
  });
  ensure(
    items.every((item, index) => index === 0 || item.id > items[index - 1].id),
    "invalid_response",
    "Activity entries are duplicated or out of order.",
  );
  return freezeValidated({
    appId,
    items,
    nextCursor: data.nextCursor as string | null,
  });
}
