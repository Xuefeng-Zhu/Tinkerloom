import type { ActionSpec, AppSpec } from "../spec/types";
import type { RuntimeRecord, RuntimeRole } from "./types";

/** A UI affordance only. Every server read and write independently authorizes. */
export function policyPermits(
  spec: AppSpec,
  role: RuntimeRole,
  archived: boolean,
  action: ActionSpec,
  record?: RuntimeRecord,
): boolean {
  if (archived || role === "viewer") return false;
  if (
    record &&
    (!record.allowedActions.includes(action.id) ||
      record.collectionId !== action.collectionId)
  )
    return false;
  if (role === "owner" || role === "builder") return true;
  if (
    action.capability === "records.create.v1" &&
    spec.collections
      .find((c) => c.id === action.collectionId)
      ?.behaviors.some((b) => b.type === "capacity.v1")
  )
    return false;
  return spec.policyPresetRequest === "groupWorkflow.v1"
    ? [
        "records.create.v1",
        "records.patch.v1",
        "assignment.assign.v1",
        "workflow.transition.v1",
      ].includes(action.capability)
    : spec.policyPresetRequest === "groupCapacitySignup.v1" &&
        ["capacity.claim.v1", "capacity.release.v1"].includes(
          action.capability,
        );
}
