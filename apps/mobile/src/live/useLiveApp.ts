import { useEffect, useMemo, useSyncExternalStore } from "react";
import { useAppContext } from "../state/AppContext";

const emptySubscribe = () => () => {};
const emptySnapshot = () => null;

export function useLiveApp(appId: string) {
  const context = useAppContext();
  const userId =
    context.state?.phase === "signedIn" && !context.state.authBusy
      ? context.state.user?.id
      : null;
  const epoch = context.controller?.sessionVersion;
  const controller = useMemo(
    () =>
      typeof epoch === "number" && userId && appId && context.registry
        ? context.registry.get(userId, appId)
        : null,
    [userId, epoch, context.registry, appId],
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
