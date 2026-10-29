import type { RuntimeLocation } from "../runtime/types";
import type { RuntimeLocationRequest } from "../runtime/location";
import { sameLocation } from "../runtime/location";

export type FullMode = "live" | "build" | "preview";
export interface FullRouteRequest {
  location: RuntimeLocationRequest;
  mode: FullMode;
  error: string | null;
  key: string;
}
/** Query values carry identities only. Repeated/invalid values fail closed. */
export function parseFullRoute(params: {
  page?: unknown;
  recordId?: unknown;
  edit?: unknown;
  mode?: unknown;
}): FullRouteRequest {
  let error: string | null = null;
  const identity = (value: unknown, pattern: RegExp) => {
    if (value === undefined) return undefined;
    if (typeof value !== "string" || !pattern.test(value)) {
      error = "This app link contains an invalid page or record identity.";
      return undefined;
    }
    return value;
  };
  const pageId = identity(params.page, /^[A-Za-z0-9_-]{1,128}$/);
  const recordId = identity(
    params.recordId,
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/,
  );
  if (params.edit !== undefined && params.edit !== "true")
    error = "This app link contains an invalid edit state.";
  if (params.edit === "true" && !recordId)
    error = "This app link requires a record identity before editing.";
  const mode: FullMode =
    params.mode === "build" || params.mode === "preview" ? params.mode : "live";
  if (
    params.mode !== undefined &&
    !["live", "build", "preview"].includes(params.mode as string)
  )
    error = "This app link contains an invalid mode.";
  const location = {
    ...(pageId ? { pageId } : {}),
    ...(recordId ? { recordId } : {}),
    ...(params.edit === "true" ? { editing: true } : {}),
  };
  return {
    location,
    mode,
    error,
    key: JSON.stringify([location, mode, error]),
  };
}
export function fullRouteParams(
  appId: string,
  location: RuntimeLocation,
  mode: FullMode,
) {
  return {
    appId,
    page: location.pageId === "__legacy__" ? undefined : location.pageId,
    recordId: location.recordId,
    edit: location.editing ? "true" : undefined,
    mode: mode === "live" ? undefined : mode,
  };
}
/** Preserve exact canonical matches. Only a record-free, nonediting request may
 * also omit its current entry page; record-page inference requires authorized get. */
export function isCurrentFullRoute(
  request: FullRouteRequest,
  location: RuntimeLocation,
  mode: FullMode,
  entryPageId: string,
): boolean {
  if (
    request.key ===
    parseFullRoute(fullRouteParams("unused", location, mode)).key
  )
    return true;
  return (
    !request.error &&
    request.mode === mode &&
    request.location.pageId === undefined &&
    request.location.recordId === undefined &&
    !request.location.editing &&
    location.recordId === undefined &&
    !location.editing &&
    sameLocation({ pageId: entryPageId }, location)
  );
}
/** In-memory ownership is scoped to one signed-in controller, never taken from URLs. */
export interface DeferredRouteAttempt {
  id: number;
  route: FullRouteRequest;
}
export interface RouteProtection {
  ownerKey: string | null;
  attempt: DeferredRouteAttempt | null;
}
export class FullRouteVisits {
  private protection: RouteProtection = { ownerKey: null, attempt: null };
  private listeners = new Set<() => void>();
  private sequence = 0;
  getProtection = () => this.protection;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  private emit(protection: RouteProtection) {
    this.protection = protection;
    for (const listener of this.listeners) listener();
  }
  protect(key: string, locked: boolean) {
    if (locked && !this.protection.ownerKey)
      this.emit({ ...this.protection, ownerKey: key });
    if (!locked && this.protection.ownerKey)
      this.emit({ ...this.protection, ownerKey: null });
  }
  /** A fresh route must return to the exact mounted component that owns unsaved input. */
  protectedReturnCount(
    currentKey: string,
    activeRouteKeys: readonly string[],
  ): number | null {
    const owner = this.protection.ownerKey;
    if (!owner || owner === currentKey) return 0;
    const current = activeRouteKeys.indexOf(currentKey),
      target = activeRouteKeys.indexOf(owner);
    return current === activeRouteKeys.length - 1 &&
      target >= 0 &&
      target < current
      ? current - target
      : null;
  }
  defer(route: FullRouteRequest) {
    const attempt = { id: ++this.sequence, route };
    this.emit({ ...this.protection, attempt });
    return attempt;
  }
  dismissAttempt(id?: number) {
    if (
      this.protection.attempt &&
      (id === undefined || this.protection.attempt.id === id)
    )
      this.emit({ ...this.protection, attempt: null });
  }
  private visits = new Map<
    string,
    { location: RuntimeLocation; mode: FullMode }
  >();
  remember(key: string, location: RuntimeLocation, mode: FullMode) {
    this.visits.set(key, { location: { ...location }, mode });
  }
  owns(key: string, location: RuntimeLocation, mode: FullMode) {
    const visit = this.visits.get(key);
    return (
      !!visit && visit.mode === mode && sameLocation(visit.location, location)
    );
  }
}
/** Invalidates delayed prompts, authorized reads and router callbacks on blur/scope change. */
export class NavigationEpoch {
  private value = 0;
  next() {
    const value = ++this.value;
    return () => value === this.value;
  }
  cancel() {
    ++this.value;
  }
}

export interface NavigationSource {
  getSnapshot(): {
    pending: unknown;
    busy: boolean;
    dirty: boolean;
    editorError: unknown;
  };
  runtime: {
    getSnapshot(): { pending: unknown; dirty: boolean; formBusy?: boolean };
  } | null;
  host: { lifetime: { active: boolean } };
  readonly hasRejectedEditorInput?: boolean;
  flush(): Promise<boolean>;
}
/** The same gate serves buttons and Expo Router's blocked Back/Forward action. */
export async function guardHostNavigation(options: {
  source: NavigationSource;
  epoch: NavigationEpoch;
  focused: () => boolean;
  action: () => void;
  prompt: (accept: () => void) => void;
  blocked: () => void;
  beforeNavigate?: () => void;
}): Promise<void> {
  const { source, epoch } = options;
  const valid = epoch.next();
  const active = () =>
    valid() && options.focused() && source.host.lifetime.active;
  const locked = () => {
    const current = source.getSnapshot();
    return (
      !!current.pending ||
      current.busy ||
      !!source.runtime?.getSnapshot().pending ||
      !!source.runtime?.getSnapshot().formBusy
    );
  };
  if (!active()) return;
  if (locked()) {
    options.blocked();
    return;
  }
  const current = source.getSnapshot();
  if (
    (current.dirty || current.editorError || source.hasRejectedEditorInput) &&
    !(await source.flush())
  )
    return;
  if (!active() || locked()) return;
  const apply = () => {
    if (!active() || locked()) return;
    options.beforeNavigate?.();
    options.action();
  };
  if (source.runtime?.getSnapshot().dirty) options.prompt(apply);
  else apply();
}
