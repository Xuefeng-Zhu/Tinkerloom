import {
  createContext,
  ReactNode,
  useContext,
  useEffect,
  useMemo,
  useSyncExternalStore,
} from "react";
import { createBackend, readPublicConfig } from "../backend";
import type { AppBackend } from "../backend/types";
import { AppController, AppState } from "./controller";
import { LiveAppRegistry } from "./liveAppController";

interface AppContextValue {
  controller: AppController | null;
  state: AppState | null;
  configurationIssues: string[];
  registry: LiveAppRegistry | null;
}

const AppContext = createContext<AppContextValue | null>(null);
const emptySubscribe = () => () => {};
const emptySnapshot = () => null;

/** The session controller lives above every route, including local previews. */
export function RootProvider({
  children,
  backend,
}: {
  children: ReactNode;
  backend?: AppBackend;
}) {
  const connection = useMemo(() => {
    if (backend) return { backend, issues: [] };
    const { config, issues } = readPublicConfig();
    return { backend: config ? createBackend(config) : null, issues };
  }, [backend]);
  const controller = useMemo(
    () => (connection.backend ? new AppController(connection.backend) : null),
    [connection.backend],
  );
  const state = useSyncExternalStore(
    controller?.subscribe ?? emptySubscribe,
    controller?.getSnapshot ?? emptySnapshot,
    controller?.getSnapshot ?? emptySnapshot,
  );
  const registry = useMemo(
    () =>
      connection.backend && controller
        ? new LiveAppRegistry(connection.backend, () =>
            controller.expireSession(),
          )
        : null,
    [connection.backend, controller],
  );
  useEffect(() => {
    registry?.keepUser(state?.user?.id ?? null);
  }, [registry, state?.user?.id]);
  useEffect(() => {
    if (!controller) return;
    void controller.bootstrap();
    return () => {
      registry?.dispose();
      controller.dispose();
    };
  }, [controller, registry]);
  const value = useMemo(
    () => ({
      controller,
      state,
      registry,
      configurationIssues: connection.issues,
    }),
    [controller, state, registry, connection.issues],
  );
  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

export function useAppContext(): AppContextValue {
  const context = useContext(AppContext);
  if (!context)
    throw new Error("Tinkerloom screens must be rendered inside RootProvider.");
  return context;
}
