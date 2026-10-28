import type { Workspace } from "../backend/types";
import type { Creation } from "../state/controller";

/** A retained command must never inherit the newly selected workspace. */
export function creationWorkspace(
  creation: Pick<Creation, "kind" | "command"> | null,
  selectedWorkspaceId: string | null,
  workspaces: Workspace[],
): { id: string | null; name: string | undefined } | null {
  if (creation?.kind !== "app") return null;
  const id = creation.command
    ? (creation.command.workspaceId ?? null)
    : selectedWorkspaceId;
  return {
    id,
    name: workspaces.find((workspace) => workspace.id === id)?.name,
  };
}
