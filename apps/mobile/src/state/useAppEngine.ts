import { useEffect, useState } from "react";
import { BackendError } from "../backend/errors";
import { useAppContext } from "./AppContext";
type Engine = "appspec.v1" | "bounded.v1";
export function useAppEngine(appId: string) {
  const context = useAppContext();
  const accountId =
    context.state?.phase === "signedIn" && !context.state.authBusy
      ? context.state.user?.id
      : null;
  const epoch = context.controller?.sessionVersion;
  const known = context.state?.apps.find((app) => app.id === appId);
  const knownEngine: Engine | null = known
    ? (known.engine ?? "bounded.v1")
    : null;
  const [attempt, setAttempt] = useState(0);
  const [result, setResult] = useState<{
    appId: string;
    accountId: string;
    epoch: number;
    attempt: number;
    engine: Engine | null;
    error: string | null;
  } | null>(null);
  useEffect(() => {
    if (!accountId || !appId || knownEngine || typeof epoch !== "number")
      return;
    let mounted = true;
    const current = () => {
      const session = context.controller?.getSnapshot();
      return (
        mounted &&
        context.controller?.sessionVersion === epoch &&
        session?.phase === "signedIn" &&
        !session.authBusy &&
        session.user?.id === accountId
      );
    };
    const read = async () => {
      try {
        const describe = context.backend?.getAppAccess;
        if (!describe)
          throw new BackendError(
            "This build cannot identify the app service.",
            "unavailable",
            "configuration",
          );
        if (!current()) return;
        const metadata = await describe.call(context.backend, appId);
        if (!current()) return;
        if (metadata.id !== appId || !metadata.engine)
          throw new BackendError(
            "The app response could not be confirmed.",
            "invalid_response",
            "invalid_response",
          );
        setResult({
          appId,
          accountId,
          epoch,
          attempt,
          engine: metadata.engine,
          error: null,
        });
      } catch (error) {
        if (!current()) return;
        if (
          error instanceof BackendError &&
          (error.kind === "unauthenticated" || error.status === 401)
        )
          context.controller?.expireSession();
        else
          setResult({
            appId,
            accountId,
            epoch,
            attempt,
            engine: null,
            error:
              error instanceof BackendError
                ? error.message
                : "This app could not be opened. Try again.",
          });
      }
    };
    void read();
    return () => {
      mounted = false;
    };
  }, [
    appId,
    accountId,
    epoch,
    knownEngine,
    attempt,
    context.backend,
    context.controller,
  ]);
  const matching =
    result?.appId === appId &&
    result.accountId === accountId &&
    result.epoch === epoch &&
    result.attempt === attempt
      ? result
      : null;
  return {
    engine: knownEngine ?? matching?.engine ?? null,
    error: matching?.error ?? null,
    reload: () => setAttempt((value) => value + 1),
  };
}
