import type { JournalStorage } from "../full/commandJournal";
import { ensure, runtimeError } from "../runtime/errors";
import type { RuntimeTransport } from "../runtime/types";
import {
  readCommand,
  readAcknowledgement,
  type ReadNotification,
  type SessionLifetime,
} from "./contracts";
export class NotificationJournal {
  private command: ReadNotification | null = null;
  private recovered = false;
  private closed = false;
  private sending = false;
  private previouslyUncertain = false;
  private recovering: Promise<ReadNotification | null> | null = null;
  phase: "sending" | "uncertain" | "rejected" | null = null;
  constructor(
    private storage: JournalStorage,
    private lifetime: SessionLifetime,
  ) {}
  get pending() {
    return this.command;
  }
  private active() {
    this.lifetime.assertActive();
    ensure(
      !this.closed,
      "disposed",
      "This account's notification journal is closed.",
    );
  }
  async recover() {
    this.active();
    if (this.recovered) return this.command;
    if (!this.recovering)
      this.recovering = (async () => {
        const value = await this.storage.read("notification-read");
        this.active();
        this.command = value === null ? null : readCommand(value);
        this.recovered = true;
        this.phase = this.command ? "uncertain" : null;
        this.previouslyUncertain = this.command !== null;
        return this.command;
      })().finally(() => {
        this.recovering = null;
      });
    return this.recovering;
  }
  async prepare(input: ReadNotification) {
    this.active();
    await this.recover();
    ensure(
      !this.command && !this.sending,
      "pending_command",
      "Resolve the retained read receipt first.",
    );
    const command = readCommand(input);
    try {
      ensure(
        await this.storage.compareAndSwap("notification-read", null, command),
        "pending_command",
        "A retained read receipt already exists. Refresh recovery before continuing.",
      );
    } catch (error) {
      this.recovered = false;
      throw error;
    }
    this.active();
    this.command = command;
    this.previouslyUncertain = false;
    this.phase = "uncertain";
  }
  async send(transport: RuntimeTransport) {
    this.active();
    ensure(
      this.command && !this.sending,
      "pending_command",
      "No read receipt is ready, or it is already being checked.",
    );
    const command = this.command;
    this.sending = true;
    this.phase = "sending";
    let clearing = false;
    try {
      const response = await transport({ ...command });
      this.active();
      readAcknowledgement(response, command);
      clearing = true;
      ensure(
        await this.storage.compareAndSwap("notification-read", command, null),
        "outcome_unknown",
        "The read result arrived, but local recovery could not be cleared.",
      );
      this.active();
      this.command = null;
      this.phase = null;
      return command;
    } catch (error) {
      if (clearing) this.recovered = false;
      if (!this.closed) {
        const failure = runtimeError(error, true);
        this.phase =
          this.previouslyUncertain ||
          failure.uncertain ||
          ["invalid_response", "outcome_unknown"].includes(failure.code)
            ? "uncertain"
            : "rejected";
        if (this.phase === "uncertain") this.previouslyUncertain = true;
      }
      throw error;
    } finally {
      this.sending = false;
    }
  }
  async acknowledgeRejection() {
    this.active();
    ensure(
      this.command && this.phase === "rejected" && !this.sending,
      "pending_command",
      "An uncertain receipt cannot be discarded; check its original outcome.",
    );
    ensure(
      await this.storage.compareAndSwap(
        "notification-read",
        this.command,
        null,
      ),
      "operation_conflict",
      "The retained receipt changed. It was not removed.",
    );
    this.active();
    this.command = null;
    this.phase = null;
  }
  dispose() {
    this.closed = true;
    this.command = null;
    this.phase = null;
  }
}
