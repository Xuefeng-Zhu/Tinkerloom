import { createDesignPreview } from "./createDesignPreview";
import type { AppSpec } from "../spec/types";
import { createIsolatedPreview } from "../runtime/createPreview";
import { PreviewRuntimeAdapter } from "../runtime/preview";
import { RuntimeError } from "../runtime/errors";
/** External sandbox lifetime, separate from the authenticated app controller. */
export class PreviewSession {
  private listeners = new Set<() => void>();
  private closed = false;
  private state: {
    session: ReturnType<typeof createIsolatedPreview>;
    restarted: boolean;
  };
  constructor(
    spec: AppSpec,
    private readonly kind: "try" | "design" = "try",
  ) {
    this.state = { session: this.create(spec), restarted: false };
  }
  private create(spec: AppSpec) {
    return this.kind === "design"
      ? createDesignPreview(spec)
      : createIsolatedPreview(spec);
  }
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  getSnapshot = () => this.state;
  update(spec: AppSpec) {
    if (!this.closed) {
      try {
        (
          this.state.session.controller.adapter as PreviewRuntimeAdapter
        ).applyPresentationSpec(spec);
        return;
      } catch (error) {
        if (
          !(error instanceof RuntimeError) ||
          error.code !== "preview_behavior_changed"
        )
          throw error;
      }
    }
    this.state.session.dispose();
    this.state = {
      session: this.create(spec),
      restarted: !this.closed,
    };
    this.closed = false;
    for (const listener of this.listeners) listener();
  }
  dispose() {
    this.closed = true;
    this.state.session.dispose();
  }
}
