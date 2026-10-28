import type { AppSpec } from "../spec/types";
import type { RuntimeAdapter } from "../runtime/types";
import { RuntimeController } from "../runtime/controller";
import { RuntimeError } from "../runtime/errors";
import { createIsolatedPreview } from "../runtime/createPreview";
/** The visual inspector shares semantic rendering but never permits record commands. */
export function createDesignPreview(spec: AppSpec) {
  const isolated = createIsolatedPreview(spec),
    adapter = isolated.controller.adapter;
  const readOnly = new Proxy(adapter, {
    get(target, key) {
      if (key === "permits") return () => false;
      if (key === "execute")
        return async () => {
          throw new RuntimeError(
            "design_read_only",
            "Switch to Try preview to test record actions.",
          );
        };
      if (key === "dispose") return () => {};
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) as RuntimeAdapter;
  const controller = new RuntimeController(readOnly, () => "design_read_only");
  return {
    controller,
    timers: isolated.timers,
    dispose() {
      controller.dispose();
      isolated.dispose();
    },
  };
}
