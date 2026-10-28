import { ensure } from "../runtime/errors";
import { checkEntry } from "./storage";
import type { AtomicHostStorage } from "./storage";
import type { HostLifetime } from "./scope";

type CipherRow =
  | { tag: string; iv: Uint8Array; data: ArrayBuffer }
  | { tag: string; removed: true };
const unavailable = () =>
  new Error("Encrypted browser storage is unavailable. No command was sent.");
const request = <T>(value: IDBRequest<T>) =>
  new Promise<T>((resolve, reject) => {
    value.onsuccess = () => resolve(value.result);
    value.onerror = () => reject(unavailable());
  });

/** IndexedDB contains nonextractable AES keys and separately authenticated ciphertext. */
export class BrowserEncryptedStorage implements AtomicHostStorage {
  private database: Promise<IDBDatabase> | null = null;
  private readonly scopeHash: Promise<string>;
  constructor(
    private readonly lifetime: HostLifetime,
    private readonly factory: IDBFactory = globalThis.indexedDB,
    private readonly cryptography: Crypto = globalThis.crypto,
  ) {
    ensure(
      factory && cryptography?.subtle,
      "storage_unavailable",
      "Encrypted browser recovery requires IndexedDB and a secure browser context.",
    );
    this.scopeHash = cryptography.subtle
      .digest("SHA-256", new TextEncoder().encode(lifetime.key))
      .then((bytes) =>
        Array.from(new Uint8Array(bytes), (byte) =>
          byte.toString(16).padStart(2, "0"),
        ).join(""),
      );
    lifetime.onDispose(() => {
      void this.database?.then((db) => db.close()).catch(() => {});
    });
  }
  private open() {
    this.lifetime.assertActive();
    this.database ??= new Promise<IDBDatabase>((resolve, reject) => {
      const pending = this.factory.open("tinkerloom.private-host.v1", 1);
      pending.onupgradeneeded = () => {
        pending.result.createObjectStore("keys");
        pending.result.createObjectStore("ciphertext");
      };
      pending.onerror = () => reject(unavailable());
      pending.onblocked = () => reject(unavailable());
      pending.onsuccess = () => {
        const db = pending.result;
        db.onversionchange = () => db.close();
        if (!this.lifetime.active) {
          db.close();
          reject(unavailable());
        } else resolve(db);
      };
    });
    return this.database;
  }
  private async entryKey(key: string) {
    return `${await this.scopeHash}:${key}`;
  }
  private async raw(key: string): Promise<CipherRow | null> {
    const db = await this.open();
    const value: unknown = await request(
      db
        .transaction("ciphertext", "readonly")
        .objectStore("ciphertext")
        .get(key),
    );
    this.lifetime.assertActive();
    if (value === undefined) return null;
    const row = value as CipherRow;
    ensure(
      row &&
        typeof row === "object" &&
        typeof row.tag === "string" &&
        (("removed" in row &&
          row.removed === true &&
          Object.keys(row).length === 2) ||
          ("iv" in row &&
            row.iv instanceof Uint8Array &&
            row.iv.byteLength === 12 &&
            row.data instanceof ArrayBuffer &&
            row.data.byteLength <= 7 * 1024 * 1024 &&
            Object.keys(row).length === 3)),
      "invalid_storage",
      "Encrypted browser state is unreadable. It has not been replaced.",
    );
    return row;
  }
  private async key(create: boolean): Promise<CryptoKey> {
    const db = await this.open(),
      name = await this.scopeHash;
    const stored = await request(
      db.transaction("keys", "readonly").objectStore("keys").get(name),
    );
    this.lifetime.assertActive();
    if (stored) return stored as CryptoKey;
    ensure(
      create,
      "missing_storage_key",
      "The encryption key for saved app state is unavailable.",
    );
    const generated = await this.cryptography.subtle.generateKey(
      { name: "AES-GCM", length: 256 },
      false,
      ["encrypt", "decrypt"],
    );
    this.lifetime.assertActive();
    return new Promise<CryptoKey>((resolve, reject) => {
      const tx = db.transaction("keys", "readwrite"),
        store = tx.objectStore("keys");
      let selected = generated;
      const old = store.get(name);
      old.onsuccess = () => {
        if (!this.lifetime.active) {
          tx.abort();
          return;
        }
        if (old.result) selected = old.result as CryptoKey;
        else store.put(generated, name);
      };
      tx.oncomplete = () => resolve(selected);
      tx.onabort = tx.onerror = () => reject(unavailable());
    });
  }
  private async plaintext(
    key: string,
    row: CipherRow | null,
  ): Promise<string | null> {
    if (!row || "removed" in row) return null;
    const secret = await this.key(false);
    const bytes = await this.cryptography.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: new Uint8Array(row.iv),
        additionalData: new TextEncoder().encode(key),
      },
      secret,
      row.data,
    );
    this.lifetime.assertActive();
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    checkEntry(text);
    return text;
  }
  async read(kind: string) {
    const key = await this.entryKey(kind);
    return this.plaintext(key, await this.raw(key));
  }
  private async compare(
    key: string,
    previous: CipherRow | null,
    next: CipherRow,
  ) {
    const db = await this.open();
    return new Promise<boolean>((resolve, reject) => {
      const tx = db.transaction("ciphertext", "readwrite"),
        store = tx.objectStore("ciphertext");
      let changed = false;
      const old = store.get(key);
      old.onsuccess = () => {
        if (!this.lifetime.active) {
          tx.abort();
          return;
        }
        if ((old.result?.tag ?? null) === (previous?.tag ?? null)) {
          store.put(next, key);
          changed = true;
        }
      };
      tx.oncomplete = () => resolve(changed);
      tx.onabort = tx.onerror = () => reject(unavailable());
    });
  }
  async change(
    kind: string,
    update: (previous: string | null) => string | null,
  ) {
    const key = await this.entryKey(kind);
    for (let attempt = 0; attempt < 8; attempt++) {
      this.lifetime.assertActive();
      const old = await this.raw(key),
        text = await this.plaintext(key, old),
        next = update(text);
      if (next === text) return;
      let row: CipherRow = {
        tag: this.cryptography.randomUUID(),
        removed: true,
      };
      if (next !== null) {
        checkEntry(next);
        const secret = await this.key(true),
          iv = this.cryptography.getRandomValues(new Uint8Array(12));
        const data = await this.cryptography.subtle.encrypt(
          {
            name: "AES-GCM",
            iv,
            additionalData: new TextEncoder().encode(key),
          },
          secret,
          new TextEncoder().encode(next),
        );
        row = { tag: this.cryptography.randomUUID(), iv, data };
      }
      this.lifetime.assertActive();
      if (await this.compare(key, old, row)) {
        this.lifetime.assertActive();
        return;
      }
    }
    throw new Error(
      "Local app state changed in another tab. Check the saved operation before retrying.",
    );
  }
}
