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
import { SharingRegistry } from "../sharing/SharingController";
import { createInvitationToken } from "../sharing/secureInvitationToken";

interface AppContextValue {
  controller: AppController | null;
  state: AppState | null;
  configurationIssues: string[];
  registry: LiveAppRegistry | null;
  sharing: SharingRegistry | null;
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
  const sharing = useMemo(
    () =>
      connection.backend && controller
        ? new SharingRegistry(connection.backend, createInvitationToken, () =>
            controller.expireSession(),
          )
        : null,
    [connection.backend, controller],
  );
  useEffect(() => {
    registry?.keepUser(state?.user?.id ?? null);
    sharing?.keepUser(state?.user?.id ?? null);
  }, [registry, sharing, state?.user?.id]);
  useEffect(() => {
    if (!controller) return;
    void controller.bootstrap();
    return () => {
      registry?.dispose();
      sharing?.dispose();
      controller.dispose();
    };
  }, [controller, registry, sharing]);
  const value = useMemo(
    () => ({
      controller,
      state,
      registry,
      sharing,
      configurationIssues: connection.issues,
    }),
    [controller, state, registry, sharing, connection.issues],
  );
  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

export function useAppContext(): AppContextValue {
  const context = useContext(AppContext);
  if (!context)
    throw new Error("Tinkerloom screens must be rendered inside RootProvider.");
  return context;
}
