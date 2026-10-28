import { useMemo } from "react";
import { useAppContext } from "../state/AppContext";
export function useFullApp(appId: string) {
  const context = useAppContext();
  const userId =
    context.state?.phase === "signedIn" && !context.state.authBusy
      ? context.state.user?.id
      : null;
  const epoch = context.controller?.sessionVersion;
  return useMemo(
    () =>
      typeof epoch === "number" && userId && appId && context.full
        ? context.full.app(userId, appId)
        : null,
    [userId, epoch, appId, context.full],
  );
}
export function useFullWorkspace(workspaceId: string) {
  const context = useAppContext();
  const userId =
    context.state?.phase === "signedIn" && !context.state.authBusy
      ? context.state.user?.id
      : null;
  const epoch = context.controller?.sessionVersion;
  return useMemo(
    () =>
      typeof epoch === "number" && userId && workspaceId && context.full
        ? context.full.workspace(userId, workspaceId)
        : null,
    [userId, epoch, workspaceId, context.full],
  );
}
