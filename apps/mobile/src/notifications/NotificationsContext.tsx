import { createContext, useContext, type ReactNode } from "react";
import type { RuntimeAdapter } from "../runtime/types";
import type {
  NotificationsController,
  VerifiedNotificationTarget,
} from "./NotificationsController";
import type { AutomationRunsController } from "./AutomationRunsController";
export interface NotificationsServices {
  inbox: NotificationsController;
  runs: (appId: string) => AutomationRunsController;
  resolveRuntime: (appId: string) => Promise<RuntimeAdapter>;
  openTarget: (target: VerifiedNotificationTarget) => void | Promise<void>;
}
const Context = createContext<NotificationsServices | null>(null);
/** Root owns account-fenced controllers and disposes them on any session epoch loss. */
export function NotificationsProvider({
  services,
  children,
}: {
  services: NotificationsServices | null;
  children: ReactNode;
}) {
  return <Context.Provider value={services}>{children}</Context.Provider>;
}
export const useNotifications = () => useContext(Context);
