import { ensure } from "../runtime/errors";
import { checkEntry } from "./storage";
import type { AtomicHostStorage } from "./storage";
import type { HostLifetime } from "./scope";

const queues = new Map<string, Promise<unknown>>();
export async function serializeHost<T>(
  key: string,
  task: () => Promise<T>,
): Promise<T> {
  const previous = queues.get(key) ?? Promise.resolve();
  const next = previous.catch(() => {}).then(task);
  queues.set(key, next);
  try {
    return await next;
  } finally {
    if (queues.get(key) === next) queues.delete(key);
  }
}
export interface EncryptedFilePorts {
  readPointer(kind: string): Promise<string | null>;
  writePointer(kind: string, name: string | null): Promise<void>;
  readFile(name: string): Promise<Uint8Array>;
  writeFile(name: string, bytes: Uint8Array): Promise<void>;
  removeFile(name: string): Promise<void>;
  seal(bytes: Uint8Array, associatedData: string): Promise<Uint8Array>;
  open(bytes: Uint8Array, associatedData: string): Promise<Uint8Array>;
  randomName(): string;
}

/** Immutable encrypted files become visible only after their small pointer commits. */
export class EncryptedFileStorage implements AtomicHostStorage {
  constructor(
    private readonly lifetime: HostLifetime,
    private readonly ports: EncryptedFilePorts,
  ) {}
  private aad(kind: string) {
    return JSON.stringify([1, this.lifetime.key, kind]);
  }
  private async pointer(kind: string) {
    const name = await this.ports.readPointer(kind);
    this.lifetime.assertActive();
    ensure(
      name === null || /^[a-f0-9-]{36}\.bin$/.test(name),
      "invalid_storage",
      "Saved encrypted app state is unreadable.",
    );
    return name;
  }
  private async readEntry(kind: string, name: string | null) {
    if (name === null) return null;
    const bytes = await this.ports.readFile(name);
    this.lifetime.assertActive();
    const plain = await this.ports.open(bytes, this.aad(kind));
    this.lifetime.assertActive();
    const text = new TextDecoder("utf-8", { fatal: true }).decode(plain);
    checkEntry(text);
    return text;
  }
  async read(kind: string) {
    return serializeHost(`${this.lifetime.key}:${kind}`, async () => {
      this.lifetime.assertActive();
      return this.readEntry(kind, await this.pointer(kind));
    });
  }
  async change(
    kind: string,
    update: (previous: string | null) => string | null,
  ) {
    return serializeHost(`${this.lifetime.key}:${kind}`, async () => {
      this.lifetime.assertActive();
      const previous = await this.pointer(kind),
        text = await this.readEntry(kind, previous),
        next = update(text);
      if (next === text) return;
      let candidate: string | null = null;
      if (next !== null) {
        checkEntry(next);
        const sealed = await this.ports.seal(
          new TextEncoder().encode(next),
          this.aad(kind),
        );
        this.lifetime.assertActive();
        candidate = this.ports.randomName();
        ensure(
          /^[a-f0-9-]{36}\.bin$/.test(candidate),
          "invalid_storage",
          "A safe encrypted file name is required.",
        );
        await this.ports.writeFile(candidate, sealed);
      }
      try {
        this.lifetime.assertActive();
        await this.ports.writePointer(kind, candidate);
      } catch (error) {
        // A failed pointer response may still have committed. Never delete a
        // potentially committed file, or treat that uncertain save as success.
        if (candidate) {
          try {
            if ((await this.ports.readPointer(kind)) !== candidate)
              await this.ports.removeFile(candidate);
          } catch {
            /* Keep encrypted orphan data when its commit is unknown. */
          }
        }
        throw error;
      }
      if (previous && previous !== candidate) {
        try {
          await this.ports.removeFile(previous);
        } catch {
          /* Pointer commit is authoritative; orphan cleanup is best effort. */
        }
      }
      this.lifetime.assertActive();
    });
  }
}
