import { useEffect, useMemo, useSyncExternalStore } from "react";
import { useAppContext } from "../state/AppContext";

const emptySubscribe = () => () => {};
const emptySnapshot = () => null;

export function useSharing(appId: string) {
  const context = useAppContext();
  const userId =
    context.state?.phase === "signedIn" ? context.state.user?.id : null;
  const controller = useMemo(
    () =>
      userId && appId ? (context.sharing?.get(userId, appId) ?? null) : null,
    [context.sharing, userId, appId],
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
    context.state?.phase === "signedIn" ? context.state.user?.id : null;
  const controller = useMemo(
    () =>
      userId && token
        ? (context.sharing?.invitation(userId, token) ?? null)
        : null,
    [context.sharing, userId, token],
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
