import type { RuntimeController, RuntimeSnapshot } from "../runtime/controller";
export type RecordRecoveryAction = "retry" | "acknowledge";
export function recordRecoveryPresentation(
  state: Pick<RuntimeSnapshot, "pending" | "accessDenied" | "error">,
) {
  const pending = state.pending;
  if (state.accessDenied || !pending) return null;
  return {
    operationId: pending.command.operationId,
    status: pending.status,
    title:
      pending.status === "sending"
        ? "Record request in progress"
        : pending.status === "uncertain"
          ? "Record outcome is unconfirmed"
          : "Record change needs review",
    message:
      pending.status === "sending"
        ? "The original record request is in progress."
        : (state.error?.message ??
          pending.error?.message ??
          "Resolve this original record request before continuing."),
    action:
      pending.status === "uncertain"
        ? ("retry" as const)
        : pending.status === "failed"
          ? ("acknowledge" as const)
          : null,
  };
}
/** The host owns recovery whenever the original Live renderer is not visible. */
export function recordRecoveryOutsideLive(
  mode: "live" | "build" | "preview",
  editorVisible: boolean,
  protectedLocationOwned: boolean,
) {
  return !protectedLocationOwned || (editorVisible && mode !== "live");
}
/** A late UI callback cannot operate on a replacement command. The controller retains authority and exact-retry semantics. */
export async function performRecordRecovery(
  controller: RuntimeController,
  operationId: string,
  action: RecordRecoveryAction,
): Promise<boolean> {
  const current = recordRecoveryPresentation(controller.getSnapshot());
  if (
    !current ||
    current.operationId !== operationId ||
    current.action !== action
  )
    return false;
  if (action === "retry") await controller.retry();
  else await controller.acknowledgeFailure();
  return true;
}

/** Local UI activity only. Every attachment has its own token, even when the same
 * runtime returns later. Detach releases the owner; a late completion cannot
 * change a replacement attachment or unlock its newer action. */
export class RecordRecoveryGate {
  private state: Readonly<{
    owner: RuntimeController | null;
    token: symbol | null;
    busy: boolean;
  }> = { owner: null, token: null, busy: false };
  private readonly listeners = new Set<() => void>();
  readonly getSnapshot = () => this.state;
  readonly subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  attach(owner: RuntimeController): () => void {
    const token = Symbol("record-recovery-attachment");
    this.update({ owner, token, busy: false });
    return () => {
      if (this.state.token === token)
        this.update({ owner: null, token: null, busy: false });
    };
  }
  async run(token: symbol, action: () => Promise<unknown>): Promise<boolean> {
    if (this.state.token !== token || this.state.busy) return false;
    this.update({ ...this.state, busy: true });
    try {
      await action();
      return true;
    } finally {
      if (this.state.token === token)
        this.update({ ...this.state, busy: false });
    }
  }
  private update(state: typeof this.state) {
    this.state = state;
    for (const listener of [...this.listeners]) listener();
  }
}
