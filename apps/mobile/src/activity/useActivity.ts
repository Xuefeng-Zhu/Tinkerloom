import { useEffect, useMemo } from "react";
import { useAppContext } from "../state/AppContext";
import { ActivityController } from "./ActivityController";

export function useActivity(appId: string) {
  const context = useAppContext();
  const owner = context.controller,
    backend = context.backend;
  const accountId =
    context.state?.phase === "signedIn" && !context.state.authBusy
      ? context.state.user?.id
      : null;
  const epoch = owner?.sessionVersion;
  const controller = useMemo(() => {
    if (
      !appId ||
      !owner ||
      !backend?.executeSpec ||
      !accountId ||
      epoch === undefined
    )
      return null;
    return new ActivityController({
      appId,
      accountId,
      epoch,
      transport: (request) => backend.executeSpec!.call(backend, request),
      readSession: () => {
        const state = owner.getSnapshot();
        return {
          accountId: state.user?.id ?? null,
          epoch: owner.sessionVersion,
          active: state.phase === "signedIn" && !state.authBusy,
        };
      },
      subscribeSession: owner.subscribe,
      onUnauthenticated: () => owner.expireSession(),
    });
  }, [appId, owner, backend, accountId, epoch]);
  useEffect(() => controller?.retain(), [controller]);
  return controller;
}
