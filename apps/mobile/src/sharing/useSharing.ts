import { useEffect, useMemo, useSyncExternalStore } from "react";
import { useAppContext } from "../state/AppContext";

const emptySubscribe = () => () => {};
const emptySnapshot = () => null;

export function useSharing(appId: string) {
  const context = useAppContext();
  const userId =
    context.state?.phase === "signedIn" && !context.state.authBusy
      ? context.state.user?.id
      : null;
  const epoch = context.controller?.sessionVersion;
  const controller = useMemo(
    () =>
      typeof epoch === "number" && userId && appId
        ? (context.sharing?.get(userId, appId) ?? null)
        : null,
    [context.sharing, userId, epoch, appId],
  );
  const state = useSyncExternalStore(
    controller?.subscribe ?? emptySubscribe,
    controller?.getSnapshot ?? emptySnapshot,
    controller?.getSnapshot ?? emptySnapshot,
  );
  useEffect(() => {
    if (controller) void controller.load();
  }, [controller]);
  return { controller, state, userId };
}

export function useInvitation(token: string) {
  const context = useAppContext();
  const userId =
    context.state?.phase === "signedIn" && !context.state.authBusy
      ? context.state.user?.id
      : null;
  const epoch = context.controller?.sessionVersion;
  const controller = useMemo(
    () =>
      typeof epoch === "number" && userId && token
        ? (context.sharing?.invitation(userId, token) ?? null)
        : null,
    [context.sharing, userId, epoch, token],
  );
  const state = useSyncExternalStore(
    controller?.subscribe ?? emptySubscribe,
    controller?.getSnapshot ?? emptySnapshot,
    controller?.getSnapshot ?? emptySnapshot,
  );
  useEffect(() => {
    if (controller) void controller.load();
  }, [controller]);
  return { controller, state };
}
