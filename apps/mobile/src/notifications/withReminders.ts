import type {
  RuntimeAdapter,
  RuntimeTransport,
  ReminderState,
} from "../runtime/types";
import { ensure, unavailable } from "../runtime/errors";
import {
  id,
  reminderPage,
  type RuleReminder,
  type SessionLifetime,
} from "./contracts";
export const reminderEffects = [
  "notifyOwner",
  "notifyAssignee",
  "notifyActiveClaimants",
] as const;
export function collapsedReminder(
  states: readonly RuleReminder[],
): ReminderState {
  if (states.length === 0)
    return { kind: "none", label: "No reminders requested for this record." };
  const label = states
    .map((rule) => {
      const state = rule.state;
      const detail =
        state === "unset"
          ? "No reminder timestamp"
          : state === "disabled"
            ? "Disabled"
            : state === "unenrolled"
              ? "Not enrolled"
              : state === "suppressed"
                ? "Suppressed"
                : state === "failed"
                  ? "Delivery failed"
                  : state === "delivered"
                    ? rule.recipientCount === 0
                      ? "Completed · no recipients"
                      : `Delivered in app (${rule.recipientCount} recipient${rule.recipientCount === 1 ? "" : "s"})`
                    : `Pending${rule.scheduledAt ? ` · due ${rule.scheduledAt}` : ""}${rule.eligible ? "" : " · currently ineligible"}`;
      return `${rule.ruleId}: ${detail}`;
    })
    .join("; ");
  // A collapsed status must not hide an unsuccessful rule behind another success.
  const kind = states.some((v) => v.state === "pending")
    ? "pending"
    : states.some((v) => v.state === "failed" || v.state === "suppressed")
      ? "cancelled"
      : states.some((v) => v.state === "delivered")
        ? "delivered"
        : "none";
  return { kind, label };
}
/** Only confirmed operational effects enable live reminder reads; declarations do not grant approval. */
export function withReminders(
  base: RuntimeAdapter,
  transport: RuntimeTransport,
  lifetime: SessionLifetime,
  options: { effects: readonly string[] },
): RuntimeAdapter {
  ensure(
    !base.preview,
    "preview_isolated",
    "An isolated preview cannot receive a live reminder transport.",
  );
  ensure(
    options.effects.every((v) => reminderEffects.includes(v as never)),
    "invalid_input",
    "Unsupported operational reminder effect.",
  );
  const operational = options.effects.length > 0,
    appId = base.appId,
    versionId = base.versionId;
  let closed = false;
  const stops = new Set<() => void>();
  let stopLifetime = () => {};
  const active = () => {
    lifetime.assertActive();
    ensure(
      !closed && base.appId === appId && base.versionId === versionId,
      "disposed",
      "This reminder runtime is closed or its immutable version changed.",
    );
  };
  const guard = async <T>(run: () => Promise<T>) => {
    active();
    const result = await run();
    active();
    return result;
  };
  const dispose = () => {
    if (closed) return;
    closed = true;
    stopLifetime();
    for (const stop of stops) stop();
    stops.clear();
    base.dispose();
  };
  stopLifetime = lifetime.onDispose?.(dispose) ?? (() => {});
  return {
    get appId() {
      return base.appId;
    },
    get versionId() {
      return base.versionId;
    },
    get spec() {
      return base.spec;
    },
    get preview() {
      return base.preview;
    },
    get role() {
      return base.role;
    },
    get archived() {
      return base.archived;
    },
    get approvedRuleIds() {
      return base.approvedRuleIds;
    },
    get features() {
      const features = new Set(base.features);
      features.delete("reminders");
      if (operational && !closed && lifetime.active) features.add("reminders");
      return features;
    },
    ...(base.setActive
      ? {
          setActive: (enabled: boolean) => {
            if (enabled) active();
            base.setActive?.(enabled);
          },
        }
      : {}),
    query: (...args) => guard(() => base.query(...args)),
    get: (...args) => guard(() => base.get(...args)),
    summary: (...args) => guard(() => base.summary(...args)),
    aggregate: (...args) => guard(() => base.aggregate(...args)),
    execute: (...args) => guard(() => base.execute(...args)),
    permits: (...args) => !closed && lifetime.active && base.permits(...args),
    members: () => guard(() => base.members()),
    readImage: (...args) => guard(() => base.readImage(...args)),
    pickImage: () => guard(() => base.pickImage()),
    uploadImage: (...args) => guard(() => base.uploadImage(...args)),
    reminderState: (recordId) =>
      guard(async () => {
        if (!operational) return unavailable("Live reminders");
        id(recordId);
        const response = await transport({
          op: "spec.reminderState",
          appId,
          versionId,
          recordId,
        });
        active();
        return collapsedReminder(
          reminderPage(
            response,
            versionId,
            base.spec.automationRequests.map((rule) => rule.id),
          ),
        );
      }),
    watch: (listener) => {
      active();
      const stop = base.watch(() => {
        if (!closed && lifetime.active) listener();
      });
      stops.add(stop);
      return () => {
        stops.delete(stop);
        stop();
      };
    },
    dispose,
  };
}
