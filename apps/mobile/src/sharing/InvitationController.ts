import { BackendError } from "../backend/errors";
import type {
  AcceptInvitation,
  AppBackend,
  InvitationPreview,
} from "../backend/types";

export interface InvitationState {
  preview: InvitationPreview | null;
  pending: AcceptInvitation | null;
  appId: string | null;
  busy: boolean;
  loading: boolean;
  error: string | null;
}
const initial = (): InvitationState => ({
  preview: null,
  pending: null,
  appId: null,
  busy: false,
  loading: false,
  error: null,
});

/** Reading an invite never grants access. Only an explicit accept sends a command. */
export class InvitationController {
  private state = initial();
  private listeners = new Set<() => void>();
  private generation = 0;
  private disposed = false;
  private pendingAppId: string | null = null;
  constructor(
    private readonly backend: AppBackend,
    readonly token: string,
    private readonly onAuthFailure: () => void,
  ) {}
  getSnapshot = () => this.state;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };
  private set(patch: Partial<InvitationState>) {
    if (this.disposed) return;
    this.state = { ...this.state, ...patch };
    for (const listener of this.listeners) listener();
  }
  private fail(error: unknown) {
    if (error instanceof BackendError && error.kind === "unauthenticated") {
      this.pendingAppId = null;
      this.set(initial());
      this.onAuthFailure();
      return;
    }
    this.set({
      busy: false,
      loading: false,
      error:
        error instanceof BackendError
          ? error.message
          : "This request could not be confirmed. Retry the same acceptance.",
    });
    if (
      error instanceof BackendError &&
      [403, 404].includes(error.status ?? 0)
    ) {
      this.pendingAppId = null;
      this.set({ preview: null, appId: null, pending: null });
    }
  }
  async load(): Promise<void> {
    if (this.disposed || this.state.busy) return;
    const generation = ++this.generation;
    this.set({ loading: true, error: null });
    try {
      const preview = await this.backend.inspectInvitation(this.token);
      if (this.disposed || generation !== this.generation) return;
      if (this.pendingAppId && preview.appId !== this.pendingAppId)
        throw new BackendError(
          "The invitation result could not be confirmed. Retry the same acceptance.",
          "invalid_response",
          "invalid_response",
        );
      this.set({
        preview,
        loading: false,
        appId: preview.accepted ? preview.appId : null,
      });
    } catch (error) {
      if (!this.disposed && generation === this.generation) this.fail(error);
    }
  }
  async accept(): Promise<void> {
    if (
      this.disposed ||
      !this.state.preview ||
      this.state.busy ||
      this.state.loading ||
      this.state.pending ||
      this.state.appId
    )
      return;
    await this.run(
      { token: this.token, operationId: this.backend.newId() },
      this.state.preview.appId,
    );
  }
  async retry(): Promise<void> {
    if (
      !this.disposed &&
      this.state.pending &&
      this.pendingAppId &&
      !this.state.busy &&
      !this.state.loading
    )
      await this.run(this.state.pending, this.pendingAppId);
  }
  private async run(command: AcceptInvitation, expectedAppId: string) {
    const generation = ++this.generation;
    this.pendingAppId = expectedAppId;
    this.set({ busy: true, pending: command, error: null });
    try {
      const result = await this.backend.acceptInvitation(command);
      if (this.disposed || generation !== this.generation) return;
      if (result.appId !== expectedAppId)
        throw new BackendError(
          "The invitation result could not be confirmed. Retry the same acceptance.",
          "invalid_response",
          "invalid_response",
          true,
        );
      this.pendingAppId = null;
      this.set({ appId: result.appId, busy: false, pending: null });
    } catch (error) {
      if (this.disposed || generation !== this.generation) return;
      const uncertain =
        !(error instanceof BackendError) ||
        error.uncertain ||
        error.code === "transaction_conflict";
      if (!uncertain) this.pendingAppId = null;
      this.set({ pending: uncertain ? command : null });
      this.fail(error);
    }
  }
  dispose() {
    this.disposed = true;
    this.generation++;
    this.pendingAppId = null;
    this.state = initial();
    this.listeners.clear();
  }
}
