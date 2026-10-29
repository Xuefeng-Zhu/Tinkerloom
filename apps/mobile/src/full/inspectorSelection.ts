import { fieldsForView } from "../spec/bindings";
import type { AppSpec } from "../spec/types";
export type InspectorTarget =
  | { kind: "app" }
  | { kind: "page"; pageId: string }
  | { kind: "view"; viewId: string }
  | { kind: "field"; collectionId: string; fieldId: string };
export function validInspectorTarget(spec: AppSpec, target: InspectorTarget) {
  switch (target.kind) {
    case "app":
      return true;
    case "page":
      return spec.navigation
        ? spec.navigation.pages.some((page) => page.id === target.pageId)
        : target.pageId === "__legacy__";
    case "view":
      return spec.views.some((view) => view.id === target.viewId);
    case "field":
      return spec.collections.some(
        (collection) =>
          collection.id === target.collectionId &&
          collection.fields.some((field) => field.id === target.fieldId),
      );
  }
}
/** Declaration metadata only: no records, runtime callbacks or authenticated reads. */
export function canvasFieldTargets(spec: AppSpec, viewId: string) {
  const view = spec.views.find((item) => item.id === viewId);
  if (!view?.collectionId) return [];
  return fieldsForView(spec, view).map((field) => ({
    collectionId: view.collectionId!,
    fieldId: field.id,
    label: field.label,
  }));
}
/** Blur and inspector transitions join the same save, and late selections are fenced. */
export class InspectorFlushQueue {
  private pending: Promise<boolean> | null = null;
  private closed = false;
  private generation = 0;
  private selection = 0;
  constructor(
    private options: {
      flush(): Promise<boolean>;
      spec(): AppSpec;
      available(): boolean;
      select(target: InspectorTarget): void;
    },
  ) {}
  configure(options: {
    flush(): Promise<boolean>;
    spec(): AppSpec;
    available(): boolean;
  }) {
    this.options = { ...this.options, ...options };
  }
  activate() {
    if (this.closed) {
      this.closed = false;
      this.generation++;
    }
  }
  get flushing() {
    return this.pending !== null;
  }
  flush(): Promise<boolean> {
    if (this.closed) return Promise.resolve(false);
    if (this.pending) return this.pending;
    if (!this.options.available()) return Promise.resolve(false);
    const generation = this.generation;
    const task = Promise.resolve()
      .then(() =>
        !this.closed &&
        generation === this.generation &&
        this.options.available()
          ? this.options.flush()
          : false,
      )
      .then(
        (saved) =>
          saved === true && !this.closed && generation === this.generation,
        () => false,
      );
    this.pending = task;
    void task.finally(() => {
      if (this.pending === task) this.pending = null;
    });
    return task;
  }
  async inspect(target: InspectorTarget): Promise<boolean> {
    const sequence = ++this.selection;
    if (
      !(await this.flush()) ||
      this.closed ||
      sequence !== this.selection ||
      !validInspectorTarget(this.options.spec(), target)
    )
      return false;
    this.options.select(target);
    return true;
  }
  async transition(change: () => void): Promise<boolean> {
    const sequence = ++this.selection;
    if (!(await this.flush()) || this.closed || sequence !== this.selection)
      return false;
    change();
    return true;
  }
  dispose() {
    this.closed = true;
    this.generation++;
    this.pending = null;
    this.selection++;
  }
}
