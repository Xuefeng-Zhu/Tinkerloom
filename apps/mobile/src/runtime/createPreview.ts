import type { AppSpec } from "../spec/types";
import { RuntimeController } from "./controller";
import { PreviewRuntimeAdapter } from "./preview";
import type { PreviewOptions } from "./preview";
import { MemoryUtilityTimerStore, UtilityTimerController } from "./timer";

/** No live/network/device dependencies can enter this factory. Dispose on candidate change. */
export function createIsolatedPreview(
  spec: AppSpec,
  options: PreviewOptions = {},
) {
  const adapter = new PreviewRuntimeAdapter(spec, options);
  let operation = 0;
  const controller = new RuntimeController(
    adapter,
    () => `preview_operation_${++operation}`,
  );
  const timers = new UtilityTimerController(new MemoryUtilityTimerStore());
  return {
    controller,
    timers,
    dispose() {
      controller.dispose();
      timers.dispose();
    },
  };
}
