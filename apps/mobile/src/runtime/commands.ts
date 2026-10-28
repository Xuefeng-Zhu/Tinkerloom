import { runtimeJsonSnapshot } from "./json";
import { ensure } from "./errors";
import type { RuntimeCommand } from "./types";
import { freezeValidated } from "./immutable";

/** The host scopes this store to endpoint + project + account + app. No tokens. */
export interface RuntimeCommandStore {
  readonly durability: "memory" | "durable";
  read(): Promise<unknown | null>;
  save(command: RuntimeCommand): Promise<void>;
  clear(operationId: string): Promise<void>;
}
export function decodeRetainedCommand(
  value: unknown,
  appId: string,
): RuntimeCommand {
  const command = runtimeJsonSnapshot(value) as Partial<RuntimeCommand>;
  ensure(
    command !== null &&
      typeof command === "object" &&
      !Array.isArray(command) &&
      command.appId === appId &&
      typeof command.operationId === "string" &&
      command.operationId.length > 0 &&
      command.operationId.length <= 128 &&
      typeof command.versionId === "string" &&
      command.versionId.length > 0 &&
      typeof command.actionId === "string" &&
      command.actionId.length > 0 &&
      command.input !== null &&
      typeof command.input === "object" &&
      !Array.isArray(command.input) &&
      (command.targetRecordId === undefined ||
        (typeof command.targetRecordId === "string" &&
          command.targetRecordId.length > 0)) &&
      (command.expectedRecordRevision === undefined ||
        (Number.isSafeInteger(command.expectedRecordRevision) &&
          command.expectedRecordRevision > 0)) &&
      Object.keys(command).every((key) =>
        [
          "appId",
          "operationId",
          "versionId",
          "actionId",
          "targetRecordId",
          "expectedRecordRevision",
          "input",
        ].includes(key),
      ),
    "invalid_saved_command",
    "The saved command is invalid or belongs to another app. It has not been sent.",
  );
  return freezeValidated(command as RuntimeCommand);
}
export class MemoryRuntimeCommandStore implements RuntimeCommandStore {
  readonly durability = "memory";
  private command: RuntimeCommand | null = null;
  async read() {
    return this.command === null ? null : runtimeJsonSnapshot(this.command);
  }
  async save(command: RuntimeCommand) {
    ensure(
      this.command === null || this.command.operationId === command.operationId,
      "pending_command",
      "The previous operation must be resolved first.",
    );
    this.command = decodeRetainedCommand(command, command.appId);
  }
  async clear(operationId: string) {
    ensure(
      this.command === null || this.command.operationId === operationId,
      "operation_conflict",
      "The stored operation changed.",
    );
    this.command = null;
  }
}
