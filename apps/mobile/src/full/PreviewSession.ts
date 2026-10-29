import { createDesignPreview } from "./createDesignPreview";
import type { AppSpec } from "../spec/types";
import { createIsolatedPreview } from "../runtime/createPreview";
import { PreviewRuntimeAdapter } from "../runtime/preview";
import type { PreviewStaticImageAssets } from "../runtime/previewImageAssets";
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
    staticImageAssets?: PreviewStaticImageAssets,
  ) {
    this.state = {
      session: this.create(spec, staticImageAssets),
      restarted: false,
    };
  }
  private create(spec: AppSpec, staticImageAssets?: PreviewStaticImageAssets) {
    return this.kind === "design"
      ? createDesignPreview(spec, { staticImageAssets })
      : createIsolatedPreview(spec, { staticImageAssets });
  }
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  getSnapshot = () => this.state;
  update(spec: AppSpec, staticImageAssets?: PreviewStaticImageAssets) {
    // Closing a scope is final; a late image load cannot reopen this sandbox.
    if (this.closed) return;
    try {
      (
        this.state.session.controller.adapter as PreviewRuntimeAdapter
      ).applyPresentationSpec(spec, staticImageAssets ?? null);
      this.state = { ...this.state };
      for (const listener of this.listeners) listener();
      return;
    } catch (error) {
      if (
        !(error instanceof RuntimeError) ||
        error.code !== "preview_behavior_changed"
      )
        throw error;
    }
    const session = this.create(spec, staticImageAssets);
    this.state.session.dispose();
    this.state = {
      session,
      restarted: true,
    };
    for (const listener of this.listeners) listener();
  }
  dispose() {
    this.closed = true;
    this.state.session.dispose();
  }
}
