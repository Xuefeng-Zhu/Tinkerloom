import { createContext, useContext } from "react";
import type { RuntimeController, RuntimeSnapshot } from "../runtime/controller";
import type {
  DeviceBridge,
  RuntimeLocation,
  RuntimeRecord,
} from "../runtime/types";
import type { ViewSpec } from "../spec/types";
import type { UtilityTimerController } from "../runtime/timer";
import type { AppearanceTokens } from "./appearance";
export interface RendererContextValue {
  controller: RuntimeController;
  state: RuntimeSnapshot;
  theme: AppearanceTokens;
  navigate: (location: RuntimeLocation) => void;
  openRecord: (view: ViewSpec, record: RuntimeRecord) => void;
  edit: (view: ViewSpec, record?: RuntimeRecord) => void;
  timers?: UtilityTimerController;
  device?: DeviceBridge;
}
export const RendererContext = createContext<RendererContextValue | null>(null);
export function useRuntime() {
  const context = useContext(RendererContext);
  if (!context)
    throw new Error("A semantic view must be inside RuntimeRenderer.");
  return context;
}
