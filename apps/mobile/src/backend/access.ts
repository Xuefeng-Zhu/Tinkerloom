import type { AppAccess, AppCapabilities, AppRole } from "./types";
import { exactKeys, invalidResponse, object } from "./validation";

const accessKeys = ["role", "archived", "capabilities"];
export function access(
  data: Record<string, unknown>,
  mutation = false,
  legacy = false,
): AppAccess {
  const present = accessKeys.filter((key) =>
    Object.prototype.hasOwnProperty.call(data, key),
  );
  if (legacy && present.length === 0) return {};
  if (
    present.length !== accessKeys.length ||
    !["owner", "builder", "member", "viewer"].includes(data.role as string) ||
    typeof data.archived !== "boolean"
  )
    invalidResponse(mutation);
  const capabilities = object(data.capabilities, mutation);
  exactKeys(
    capabilities,
    ["editDefinition", "share", "writeRecords", "archive", "revokeAccess"],
    mutation,
  );
  const builder = data.role === "owner" || data.role === "builder";
  const expected: AppCapabilities = {
    editDefinition: builder && !data.archived,
    share: builder && !data.archived,
    writeRecords: builder && !data.archived,
    archive: data.role === "owner" && !data.archived,
    revokeAccess: builder,
  };
  if (
    Object.entries(expected).some(([key, value]) => capabilities[key] !== value)
  )
    invalidResponse(mutation);
  return {
    role: data.role as AppRole,
    archived: data.archived,
    capabilities: expected,
  };
}
