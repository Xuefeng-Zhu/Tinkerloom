/** Raw inspector text outlives invalid semantic edits and failed saves, without replaying writes. */
export class InspectorTextDraft {
  private draft: string | null = null;
  private focused = false;
  private valid = true;
  private interaction = 0;
  private lifetime = 0;
  private closed = false;
  private listeners = new Set<() => void>();
  constructor(
    private value: string,
    private identity: string,
    private resetEpoch: number,
  ) {}
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  getSnapshot = () => this.draft ?? this.value;
  get rejected() {
    return this.draft !== null && !this.valid;
  }
  matches(identity: string, resetEpoch: number) {
    return this.identity === identity && this.resetEpoch === resetEpoch;
  }
  private emit() {
    for (const listener of this.listeners) listener();
  }
  configure(value: string, identity: string, resetEpoch: number) {
    if (this.closed) return;
    const reset = !this.matches(identity, resetEpoch);
    this.value = value;
    if (reset) {
      this.identity = identity;
      this.resetEpoch = resetEpoch;
      this.draft = null;
      this.valid = true;
      this.focused = false;
      this.interaction++;
    }
    this.emit();
  }
  activate() {
    if (this.closed) {
      this.closed = false;
      this.lifetime++;
    }
  }
  focus() {
    if (!this.closed) {
      this.focused = true;
      this.interaction++;
    }
  }
  change(text: string, accepted = true) {
    if (this.closed) return;
    this.draft = text;
    this.valid = accepted;
    this.interaction++;
    this.emit();
  }
  accept() {
    if (this.closed) return;
    this.valid = true;
    this.emit();
  }
  reject() {
    if (this.closed) return;
    this.valid = false;
    this.emit();
  }
  async blur(flush: () => Promise<boolean>): Promise<boolean> {
    if (this.closed) return false;
    this.focused = false;
    const interaction = this.interaction,
      lifetime = this.lifetime;
    let saved = false;
    try {
      saved = await flush();
    } catch {
      /* Rejected flush preserves raw text for repair. */
    }
    if (
      this.closed ||
      this.lifetime !== lifetime ||
      this.interaction !== interaction ||
      this.focused ||
      !this.valid ||
      !saved
    )
      return false;
    this.draft = null;
    this.emit();
    return true;
  }
  dispose() {
    this.closed = true;
    this.lifetime++;
    this.draft = null;
    this.value = "";
    this.valid = false;
    this.listeners.clear();
  }
}

/** Mounted raw inputs can block a declaration flush without exposing their contents. */
export class InspectorInputRegistry {
  private inputs = new Set<InspectorTextDraft>();
  private listeners = new Set<() => void>();
  private ready = true;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  private changed() {
    const ready = this.canFlush();
    if (ready === this.ready) return;
    this.ready = ready;
    for (const listener of this.listeners) listener();
  }
  register = (input: InspectorTextDraft) => {
    this.inputs.add(input);
    const unsubscribe = input.subscribe(() => this.changed());
    this.changed();
    return () => {
      unsubscribe();
      this.inputs.delete(input);
      this.changed();
    };
  };
  canFlush = () => [...this.inputs].every((input) => !input.rejected);
}
