import { useEffect, useMemo, useSyncExternalStore } from "react";
import { useAppContext } from "../state/AppContext";

const emptySubscribe = () => () => {};
const emptySnapshot = () => null;

export function useLiveApp(appId: string) {
  const context = useAppContext();
  const userId =
    context.state?.phase === "signedIn" ? context.state.user?.id : null;
  const controller = useMemo(
    () =>
      userId && appId && context.registry
        ? context.registry.get(userId, appId)
        : null,
    [userId, context.registry, appId],
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
