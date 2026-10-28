import type { ScopedHostStorage } from "../host/storage";
import { ensure, runtimeError, type RuntimeError } from "../runtime/errors";
import { runtimeJsonSnapshot } from "../runtime/json";
import { freezeValidated } from "../runtime/immutable";
import type { RuntimeTransport } from "../runtime/types";
import { row, same, text } from "./contracts";

export interface JournalStorage {
  read(kind: string): Promise<unknown | null>;
  compareAndSwap(
    kind: string,
    expected: unknown | null,
    next: unknown | null,
  ): Promise<boolean>;
}
export type CommandPhase = "sending" | "uncertain" | "rejected";
export interface RetainedFullCommand {
  version: 1;
  request: Record<string, unknown>;
  context: Record<string, unknown>;
}
const operations = [
  "spec.saveDraft",
  "spec.publish",
  "spec.generate",
  "spec.keepPrevious",
  "spec.instantiate",
  "spec.remix",
  "spec.setPinned",
  "spec.createApp",
];
export function decodeCommand(input: unknown): RetainedFullCommand {
  const data = row(runtimeJsonSnapshot(input)),
    request = row(data.request),
    context = row(data.context);
  ensure(
    data.version === 1 &&
      Object.keys(data).length === 3 &&
      operations.includes(String(request.op)),
    "invalid_saved_command",
    "The retained operation is invalid. It has not been replaced.",
  );
  text(request.operationId, 128);
  return freezeValidated({ version: 1, request, context });
}
/** One immutable operation at a time. Recovery only reads; explicit retry replays exact bytes. */
export class FullCommandJournal {
  private value: RetainedFullCommand | null = null;
  private phase: CommandPhase | null = null;
  private recovered = false;
  private running = false;
  private closed = false;
  constructor(
    private storage: JournalStorage | ScopedHostStorage,
    private kind = "full-command",
    private validate: (command: RetainedFullCommand) => void = () => {},
  ) {}
  get pending() {
    return this.value;
  }
  get status() {
    return this.phase;
  }
  private active() {
    ensure(!this.closed, "disposed", "This account scope is closed.");
  }
  async recover() {
    this.active();
    if (this.recovered) return this.value;
    const value = await this.storage.read(this.kind);
    this.active();
    const command = value === null ? null : decodeCommand(value);
    if (command) this.validate(command);
    this.value = command;
    this.phase = this.value ? "uncertain" : null;
    this.recovered = true;
    return this.value;
  }
  async prepare(
    request: Record<string, unknown>,
    context: Record<string, unknown> = {},
  ) {
    this.active();
    await this.recover();
    this.active();
    ensure(
      !this.value && !this.running,
      "pending_command",
      "Resolve the retained operation before starting another.",
    );
    const command = decodeCommand({ version: 1, request, context });
    this.validate(command);
    ensure(
      await this.storage.compareAndSwap(this.kind, null, command),
      "pending_command",
      "Another retained operation exists. Reopen recovery before continuing.",
    );
    this.active();
    this.value = command;
    this.phase = "uncertain";
    return command;
  }
  async send<T>(
    transport: RuntimeTransport,
    decode: (response: unknown, command: RetainedFullCommand) => T,
  ): Promise<T> {
    this.active();
    ensure(
      this.value && !this.running,
      "pending_command",
      "No operation is ready, or it is already being checked.",
    );
    const command = this.value;
    this.running = true;
    this.phase = "sending";
    try {
      const response = await transport(command.request);
      this.active();
      const result = decode(response, command);
      this.active();
      ensure(
        await this.storage.compareAndSwap(this.kind, command, null),
        "outcome_unknown",
        "The response arrived, but local recovery could not be cleared.",
      );
      this.active();
      this.value = null;
      this.phase = null;
      return result;
    } catch (error) {
      if (!this.closed) {
        const failure = runtimeError(error, true);
        this.phase =
          failure.uncertain ||
          failure.code === "invalid_response" ||
          failure.code === "outcome_unknown"
            ? "uncertain"
            : "rejected";
      }
      throw error;
    } finally {
      this.running = false;
    }
  }
  async acknowledgeRejection() {
    this.active();
    ensure(
      this.value && this.phase === "rejected" && !this.running,
      "pending_command",
      "An uncertain operation must be retried; it cannot be discarded.",
    );
    const command = this.value;
    ensure(
      await this.storage.compareAndSwap(this.kind, command, null),
      "operation_conflict",
      "The retained operation changed. It was not removed.",
    );
    this.active();
    this.value = null;
    this.phase = null;
  }
  matches(request: Record<string, unknown>) {
    return this.value !== null && same(this.value.request, request);
  }
  dispose() {
    this.closed = true;
    this.value = null;
    this.phase = null;
  }
}
export function fullError(error: unknown, mutation = false): RuntimeError {
  return runtimeError(error, mutation);
}
