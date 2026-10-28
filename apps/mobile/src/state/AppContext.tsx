import {
  createContext,
  ReactNode,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useSyncExternalStore,
} from "react";
import { createBackend, readPublicConfig } from "../backend";
import type { AppBackend } from "../backend/types";
import { AppController, AppState } from "./controller";
import { LiveAppRegistry } from "./liveAppController";
import { SharingRegistry } from "../sharing/SharingController";
import { FullRegistry } from "../full/FullRegistry";
import type { HostScope } from "../host/scope";
import { createInvitationToken } from "../sharing/secureInvitationToken";

interface AppContextValue {
  controller: AppController | null;
  state: AppState | null;
  configurationIssues: string[];
  registry: LiveAppRegistry | null;
  sharing: SharingRegistry | null;
  full: FullRegistry | null;
  backend: AppBackend | null;
}

const AppContext = createContext<AppContextValue | null>(null);
const emptySubscribe = () => () => {};
const emptySnapshot = () => null;

/** The session controller lives above every route, including local previews. */
export function RootProvider({
  children,
  backend,
  backendScope,
}: {
  children: ReactNode;
  backend?: AppBackend;
  backendScope?: Pick<HostScope, "endpoint" | "projectId">;
}) {
  const connection = useMemo(() => {
    const { config, issues } = readPublicConfig();
    return {
      backend: backend ?? (config ? createBackend(config) : null),
      issues: backend ? [] : issues,
      scope: backendScope ?? config,
    };
  }, [backend, backendScope]);
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
  const full = useMemo(() => {
    const service = connection.backend;
    return service?.executeSpec && connection.scope && controller
      ? new FullRegistry({
          backend: service,
          scope: connection.scope,
          readSession: () => {
            const current = controller.getSnapshot();
            return {
              accountId: current.user?.id ?? null,
              epoch: controller.sessionVersion,
              active: current.phase === "signedIn" && !current.authBusy,
            };
          },
          onUnauthenticated: () => controller.expireSession(),
        })
      : null;
  }, [connection.backend, connection.scope, controller]);
  const mounts = useRef(new Map<AppController, number>());
  useEffect(() => {
    if (!controller) return;
    const counts = mounts.current;
    counts.set(controller, (counts.get(controller) ?? 0) + 1);
    // Observe authentication synchronously, before another route can dispatch.
    const sync = () => {
      const current = controller.getSnapshot();
      const account =
        current.phase === "signedIn" && !current.authBusy
          ? (current.user?.id ?? null)
          : null;
      registry?.keepUser(account);
      sharing?.keepUser(account);
      full?.syncSession();
    };
    const unsubscribe = controller.subscribe(sync);
    sync();
    void controller.bootstrap();
    return () => {
      unsubscribe();
      counts.set(controller, (counts.get(controller) ?? 1) - 1);
      queueMicrotask(() => {
        if (counts.get(controller) !== 0) return;
        counts.delete(controller);
        registry?.dispose();
        sharing?.dispose();
        full?.dispose();
        controller.dispose();
      });
    };
  }, [controller, registry, sharing, full]);
  const value = useMemo(
    () => ({
      controller,
      state,
      registry,
      sharing,
      full,
      backend: connection.backend,
      configurationIssues: connection.issues,
    }),
    [
      controller,
      state,
      registry,
      sharing,
      full,
      connection.backend,
      connection.issues,
    ],
  );
  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

export function useAppContext(): AppContextValue {
  const context = useContext(AppContext);
  if (!context)
    throw new Error("Tinkerloom screens must be rendered inside RootProvider.");
  return context;
}
