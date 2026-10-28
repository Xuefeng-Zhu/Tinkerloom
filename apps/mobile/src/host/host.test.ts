import assert from "node:assert/strict";
import test from "node:test";
import { randomUUID, webcrypto } from "node:crypto";
import { HostLifetime } from "./scope";
import { hostStores } from "./storage";
import type { AtomicHostStorage } from "./storage";
import { EncryptedFileStorage, serializeHost } from "./encryptedFiles";
import type { EncryptedFilePorts } from "./encryptedFiles";
import { ScopedDeviceBridge } from "./device";
import type { DeviceDriver } from "./device";
import type { DeviceControl } from "../spec/types";
import type { RuntimeCommand, DeviceState } from "../runtime/types";
import { readyTimer } from "../runtime/timer";
import { requireTorchPermission } from "./torchPermission";

const scope = {
  endpoint: "https://cloud.example/v1",
  projectId: "project",
  accountId: "account",
  appId: "app",
};
const command: RuntimeCommand = {
  appId: "app",
  operationId: "operation",
  versionId: "immutable-version",
  actionId: "create",
  input: { title: "Private retained text", done: false },
};
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((accept) => {
    resolve = accept;
  });
  return { promise, resolve };
}
class AtomicMemory implements AtomicHostStorage {
  readonly values = new Map<string, string>();
  failWrite = false;
  readonly lock = randomUUID();
  async read(key: string) {
    return this.values.get(key) ?? null;
  }
  change(key: string, update: (text: string | null) => string | null) {
    return serializeHost(`${this.lock}:${key}`, async () => {
      if (this.failWrite) throw new Error("Storage did not commit");
      const next = update(this.values.get(key) ?? null);
      if (next === null) this.values.delete(key);
      else this.values.set(key, next);
    });
  }
}
function memory() {
  const port = new AtomicMemory(),
    lifetime = new HostLifetime(scope);
  return { port, ...hostStores(lifetime, port) };
}

test("host scope normalization fences every backend, project, account and app boundary", async () => {
  const original = memory();
  await original.commands.save(command);
  assert.equal(
    new HostLifetime({ ...scope, endpoint: scope.endpoint + "/" }).key,
    original.lifetime.key,
  );
  for (const changed of [
    { endpoint: "https://other.example/v1" },
    { projectId: "other" },
    { accountId: "other" },
    { appId: "other" },
  ]) {
    const foreign = hostStores(
      new HostLifetime({ ...scope, ...changed }),
      original.port,
    );
    await assert.rejects(foreign.commands.read(), /different app scope/);
  }
  assert.throws(
    () =>
      new HostLifetime({
        ...scope,
        endpoint: "https://user:password@example.test/v1",
      }),
  );
  assert.throws(
    () => new HostLifetime({ ...scope, endpoint: "http://remote.example/v1" }),
  );
});

test("saved operations restore without execution and cannot replace original identity or input", async () => {
  const first = memory();
  await first.commands.save(command);
  first.lifetime.dispose();
  const restored = hostStores(new HostLifetime(scope), first.port);
  assert.deepEqual(await restored.commands.read(), command);
  await restored.commands.save({
    ...command,
    input: { done: false, title: "Private retained text" },
  });
  await assert.rejects(
    restored.commands.save({ ...command, operationId: "replacement" }),
    /previous saved operation/,
  );
  await assert.rejects(
    restored.commands.save({ ...command, input: { title: "Changed" } }),
    /original input/,
  );
  await assert.rejects(
    restored.commands.clear("wrong-operation"),
    /not been removed/,
  );
  assert.deepEqual(await restored.commands.read(), command);
  await restored.commands.clear(command.operationId);
  assert.equal(await restored.commands.read(), null);
});

test("storage failures preserve an old command and corrupt envelopes are never silently replaced", async () => {
  const host = memory();
  await host.commands.save(command);
  host.port.failWrite = true;
  await assert.rejects(host.commands.clear(command.operationId));
  assert.deepEqual(await host.commands.read(), command);
  host.port.failWrite = false;
  host.port.values.set("command", "broken-json");
  await assert.rejects(host.commands.read(), /unreadable/);
  await assert.rejects(host.commands.save(command), /unreadable/);
  assert.equal(host.port.values.get("command"), "broken-json");
});

test("a late private storage read cannot escape a closed account lifetime", async () => {
  const host = memory();
  await host.commands.save(command);
  const pending = deferred<string | null>();
  host.port.read = () => pending.promise;
  const reading = host.commands.read();
  host.lifetime.dispose();
  pending.resolve(host.port.values.get("command")!);
  await assert.rejects(reading, /scope is closed/);
});

test("generic builder envelopes snapshot exact review content and compare-and-swap cannot replace a newer command", async () => {
  const host = memory();
  const review = {
    operationId: "publish",
    appId: "app",
    expectedRevision: 7,
    candidateRevision: 11,
    expectedPublishedRevision: 9,
    hash: "reviewed-hash",
    content: { title: "Reviewed title" },
  };
  const saving = host.storage.write("builder-command", review);
  review.content.title = "Changed while persisting";
  await saving;
  const restored = (await host.storage.read(
    "builder-command",
  )) as typeof review;
  assert.equal(restored.content.title, "Reviewed title");
  assert.equal(
    await host.storage.compareAndSwap(
      "builder-command",
      { ...restored, operationId: "old" },
      null,
    ),
    false,
  );
  assert.deepEqual(await host.storage.read("builder-command"), restored);
  assert.equal(
    await host.storage.compareAndSwap("builder-command", restored, {
      ...restored,
      state: "confirmed",
    }),
    true,
  );
  assert.equal(
    await host.storage.compareAndSwap("builder-command", restored, null),
    false,
  );
});

test("generic persistence rejects JSON hooks before storage and preserves the prior command", async () => {
  const host = memory();
  await host.storage.write("builder-command", { operationId: "original" });
  let calls = 0;
  assert.throws(() =>
    host.storage.write("builder-command", {
      toJSON() {
        calls++;
        return {};
      },
    }),
  );
  assert.equal(calls, 0);
  assert.deepEqual(await host.storage.read("builder-command"), {
    operationId: "original",
  });
});

test("utility timers preserve deadlines and allow an explicit reset of invalid timer payloads", async () => {
  const host = memory();
  const running = {
    ...readyTimer(),
    phase: "running" as const,
    deadline: "2026-10-28T19:30:00Z",
  };
  await host.timers.write("focus", running);
  assert.deepEqual(
    await hostStores(new HostLifetime(scope), host.port).timers.read("focus"),
    running,
  );
  const envelope = JSON.parse(host.port.values.get("timer:focus")!);
  envelope.payload = { version: 17, phase: "running" };
  host.port.values.set("timer:focus", JSON.stringify(envelope));
  await assert.rejects(host.timers.read("focus"), /saved timer is invalid/);
  await host.timers.write("focus", readyTimer(10));
  assert.deepEqual(await host.timers.read("focus"), readyTimer(10));
});

async function encryptedFiles() {
  const pointers = new Map<string, string>(),
    files = new Map<string, Uint8Array>();
  const cryptography = webcrypto as unknown as Crypto;
  const key = await cryptography.subtle.generateKey(
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
  const ports: EncryptedFilePorts = {
    readPointer: async (kind) => pointers.get(kind) ?? null,
    writePointer: async (kind, name) => {
      if (name === null) pointers.delete(kind);
      else pointers.set(kind, name);
    },
    readFile: async (name) => {
      assert.ok(files.has(name));
      return files.get(name)!.slice();
    },
    writeFile: async (name, bytes) => {
      assert.equal(files.has(name), false);
      files.set(name, bytes.slice());
    },
    removeFile: async (name) => {
      files.delete(name);
    },
    async seal(bytes, aad) {
      const iv = cryptography.getRandomValues(new Uint8Array(12));
      const encrypted = new Uint8Array(
        await cryptography.subtle.encrypt(
          {
            name: "AES-GCM",
            iv,
            additionalData: new TextEncoder().encode(aad),
          },
          key,
          new Uint8Array(bytes),
        ),
      );
      const combined = new Uint8Array(12 + encrypted.length);
      combined.set(iv);
      combined.set(encrypted, 12);
      return combined;
    },
    async open(bytes, aad) {
      return new Uint8Array(
        await cryptography.subtle.decrypt(
          {
            name: "AES-GCM",
            iv: new Uint8Array(bytes.slice(0, 12)),
            additionalData: new TextEncoder().encode(aad),
          },
          key,
          new Uint8Array(bytes.slice(12)),
        ),
      );
    },
    randomName: () => `${randomUUID()}.bin`,
  };
  return { pointers, files, ports };
}

test("encrypted file adapter restores a five-MiB command with only a tiny pointer and authenticated ciphertext", async () => {
  const disk = await encryptedFiles(),
    lifetime = new HostLifetime(scope);
  const host = hostStores(
    lifetime,
    new EncryptedFileStorage(lifetime, disk.ports),
  );
  const large = {
    ...command,
    input: { body: "Private large input ".repeat(270000) },
  };
  await host.commands.save(large);
  assert.ok(disk.pointers.get("command")!.length < 64);
  assert.equal(
    Buffer.from([...disk.files.values()][0]).includes(
      Buffer.from("Private large input"),
    ),
    false,
  );
  lifetime.dispose();
  const next = new HostLifetime(scope);
  assert.deepEqual(
    await hostStores(
      next,
      new EncryptedFileStorage(next, disk.ports),
    ).commands.read(),
    large,
  );
  const other = new HostLifetime({ ...scope, accountId: "other" });
  await assert.rejects(
    hostStores(
      other,
      new EncryptedFileStorage(other, disk.ports),
    ).commands.read(),
  );
});

test("a lost pointer-write response retains a committed encrypted file for exact recovery", async () => {
  const disk = await encryptedFiles(),
    lifetime = new HostLifetime(scope);
  const host = hostStores(
    lifetime,
    new EncryptedFileStorage(lifetime, disk.ports),
  );
  const write = disk.ports.writePointer;
  disk.ports.writePointer = async (kind, value) => {
    await write(kind, value);
    throw new Error("Lost local commit response");
  };
  await assert.rejects(host.commands.save(command), /Lost local commit/);
  assert.equal(disk.files.size, 1);
  assert.deepEqual(await host.commands.read(), command);
});

test("account disposal during encryption prevents pointer commit and competing commands cannot overwrite each other", async () => {
  const disk = await encryptedFiles(),
    lifetime = new HostLifetime(scope);
  const encrypted = deferred<Uint8Array>();
  disk.ports.seal = () => encrypted.promise;
  const host = hostStores(
    lifetime,
    new EncryptedFileStorage(lifetime, disk.ports),
  );
  const saving = host.commands.save(command);
  await new Promise((resolve) => setTimeout(resolve, 0));
  lifetime.dispose();
  encrypted.resolve(new Uint8Array([1, 2, 3]));
  await assert.rejects(saving, /scope is closed/);
  assert.equal(disk.pointers.size, 0);
  assert.equal(disk.files.size, 0);

  const second = memory();
  const results = await Promise.allSettled([
    second.commands.save(command),
    second.commands.save({ ...command, operationId: "other" }),
  ]);
  assert.equal(
    results.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.deepEqual(await second.commands.read(), command);
});

function deviceHost() {
  const host = memory();
  const applied: { control: DeviceControl; value: unknown; lease: string }[] =
      [],
    released: DeviceControl[] = [];
  let readCount = 0;
  const driver: DeviceDriver = {
    supported: async () => [
      "battery",
      "device",
      "flashlight",
      "brightness",
      "keepAwake",
      "haptics",
    ],
    read: async () => {
      readCount++;
      return { batteryLevel: 0.6, model: "Hidden extra field" };
    },
    apply: async (control, value, lease) => {
      applied.push({ control, value, lease });
    },
    release: async (control) => {
      released.push(control);
    },
    openSettings: async () => {},
  };
  const bridge = new ScopedDeviceBridge(
    host.storage,
    driver,
    ["battery", "device", "flashlight", "brightness", "keepAwake", "haptics"],
    "lease",
  );
  return {
    ...host,
    driver,
    bridge,
    applied,
    released,
    readCount: () => readCount,
  };
}

test("device access starts off and reads only explicitly granted fields without exposing extra driver values", async () => {
  const host = deviceHost();
  host.bridge.setActive(true);
  await host.bridge.initialize();
  assert.deepEqual(host.bridge.available, []);
  await assert.rejects(host.bridge.read(["batteryLevel"]), /Enable this app/);
  await assert.rejects(
    host.bridge.control("flashlight", true),
    /Enable this app/,
  );
  assert.equal(host.readCount(), 0);
  assert.equal(host.applied.length, 0);
  await host.bridge.setGrant("battery", true);
  assert.deepEqual(await host.bridge.read(["batteryLevel"]), {
    batteryLevel: 0.6,
  });
  await assert.rejects(host.bridge.read(["model"]));
  assert.equal(host.readCount(), 1);
});

test("revocation fences late device values and remains off when consent persistence fails", async () => {
  const host = deviceHost();
  await host.bridge.initialize();
  host.bridge.setActive(true);
  await host.bridge.setGrant("battery", true);
  const pending = deferred<DeviceState>();
  host.driver.read = () => pending.promise;
  const reading = host.bridge.read(["batteryLevel"]);
  host.port.failWrite = true;
  await assert.rejects(host.bridge.setGrant("battery", false));
  pending.resolve({ batteryLevel: 0.8 });
  await assert.rejects(reading, /changed before/);
  assert.deepEqual(host.bridge.available, []);
  assert.deepEqual(host.bridge.getSnapshot().granted, []);
});

test("backgrounding releases an in-flight control and foregrounding never replays it", async () => {
  const host = deviceHost();
  await host.bridge.initialize();
  host.bridge.setActive(true);
  await host.bridge.setGrant("brightness", true);
  const applying = deferred<void>();
  const started = deferred<void>();
  host.driver.apply = async (control, value, lease) => {
    host.applied.push({ control, value, lease });
    started.resolve();
    await applying.promise;
  };
  const request = host.bridge.control("brightness", 0.7);
  await started.promise;
  host.bridge.setForeground(false);
  applying.resolve();
  await assert.rejects(request, /interrupted/);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.ok(host.released.includes("brightness"));
  assert.deepEqual(host.bridge.available, []);
  host.bridge.setForeground(true);
  assert.equal(host.applied.length, 1);
});

test("scope disposal clears local device grants, fences late reads and releases controls", async () => {
  const host = deviceHost();
  await host.bridge.initialize();
  host.bridge.setActive(true);
  await host.bridge.setGrant("battery", true);
  const pending = deferred<DeviceState>();
  host.driver.read = () => pending.promise;
  const reading = host.bridge.read(["batteryLevel"]);
  host.lifetime.dispose();
  pending.resolve({ batteryLevel: 0.9 });
  await assert.rejects(reading, /scope is closed/);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(host.bridge.available, []);
  assert.deepEqual(host.bridge.getSnapshot().granted, []);
  assert.equal(host.released.length, 4);
});

test("device controls reject arbitrary operations and invalid values before invoking the driver", async () => {
  const host = deviceHost();
  await host.bridge.initialize();
  host.bridge.setActive(true);
  await host.bridge.setGrant("brightness", true);
  await host.bridge.setGrant("flashlight", true);
  for (const [control, value] of [
    ["brightness", NaN],
    ["brightness", 2],
    ["flashlight", 1],
    ["deleteFiles", true],
  ] as const)
    await assert.rejects(host.bridge.control(control as DeviceControl, value));
  assert.deepEqual(host.applied, []);
});

test("granting camera permission never automatically resumes a flashlight write", async () => {
  let granted = false,
    prompts = 0,
    writes = 0;
  const port = {
    get: async () => ({ granted, canAskAgain: true }),
    request: async () => {
      prompts++;
      granted = true;
      return { granted };
    },
  };
  async function turnOn() {
    await requireTorchPermission(port);
    writes++;
  }
  await assert.rejects(turnOn(), /explicitly/);
  assert.equal(prompts, 1);
  assert.equal(writes, 0);
  await turnOn();
  assert.equal(writes, 1);
  assert.equal(prompts, 1);
});

test("a permission lookup completed after account closure cannot open a permission prompt", async () => {
  const pending = deferred<{ granted: boolean; canAskAgain: boolean }>();
  let active = true,
    prompts = 0;
  const checking = requireTorchPermission(
    {
      get: () => pending.promise,
      request: async () => {
        prompts++;
        return { granted: true };
      },
    },
    () => {
      if (!active) throw new Error("Account scope closed");
    },
  );
  active = false;
  pending.resolve({ granted: false, canAskAgain: true });
  await assert.rejects(checking, /Account scope closed/);
  assert.equal(prompts, 0);
});

test("leaving a control view fences a pending permission lookup before its cleanup queue runs", async () => {
  const host = deviceHost();
  await host.bridge.initialize();
  host.bridge.setActive(true);
  await host.bridge.setGrant("flashlight", true);
  const permission = deferred<{ granted: boolean; canAskAgain: boolean }>(),
    started = deferred<void>();
  let prompts = 0;
  host.driver.apply = async (_control, _value, _lease, current) => {
    await requireTorchPermission(
      {
        get: () => {
          started.resolve();
          return permission.promise;
        },
        request: async () => {
          prompts++;
          return { granted: true };
        },
      },
      () => {
        if (!current()) throw new Error("View is inactive");
      },
    );
  };
  const request = host.bridge.control("flashlight", true);
  await started.promise;
  const releasing = host.bridge.release("flashlight");
  permission.resolve({ granted: false, canAskAgain: true });
  await assert.rejects(request, /View is inactive/);
  await releasing;
  assert.equal(prompts, 0);
  assert.ok(host.released.includes("flashlight"));
});
