import assert from "node:assert/strict";
import test from "node:test";
import { collectPickedImage } from "./picker";
import { ORIGINAL_BYTES, CHUNK_BYTES } from "./types";
import { HostLifetime } from "../host/scope";
import { createPrivateMediaPorts } from "./platform.web";
import { RuntimeError } from "../runtime/errors";
const failure = (code: string) => (error: unknown) =>
  error instanceof RuntimeError && error.code === code;
const jpeg = (length: number) => {
  const bytes = new Uint8Array(length).fill(34);
  bytes.set([255, 216, 255]);
  return bytes;
};
const active = () => {};

test("known oversize and unsupported picker metadata are rejected before any byte IO", async () => {
  let reads = 0;
  const read = async () => {
    reads++;
    return jpeg(12);
  };
  for (const size of [ORIGINAL_BYTES + 1, Number.MAX_SAFE_INTEGER])
    await assert.rejects(
      collectPickedImage(read, active, [size], "image/jpeg"),
      failure("media_too_large"),
    );
  for (const size of [-1, 0, 1.5, NaN])
    await assert.rejects(
      collectPickedImage(read, active, [size], "image/jpeg"),
      failure("media_unsupported"),
    );
  await assert.rejects(
    collectPickedImage(read, active, [12], "image/svg+xml"),
    failure("media_unsupported"),
  );
  assert.equal(reads, 0);
});

test("a five MiB original uses bounded reads plus one EOF byte and clears intermediate buffers", async () => {
  const original = jpeg(ORIGINAL_BYTES),
    chunks: Uint8Array[] = [],
    requests: number[] = [];
  let offset = 0;
  const picked = await collectPickedImage(
    async (maximum) => {
      requests.push(maximum);
      const chunk = original.slice(offset, offset + maximum);
      chunks.push(chunk);
      offset += chunk.length;
      return chunk;
    },
    active,
    [ORIGINAL_BYTES],
    "image/jpeg",
  );
  assert.deepEqual(picked.bytes, original);
  assert.equal(picked.name, "Selected private image");
  assert.equal(requests.length, 21);
  assert.equal(requests.at(-1), 1);
  assert(requests.every((length) => length <= CHUNK_BYTES));
  assert(chunks.every((chunk) => chunk.every((byte) => byte === 0)));
});

test("unknown or lying file length cannot exceed the five MiB plus one byte read bound", async () => {
  const chunks: Uint8Array[] = [];
  let readBytes = 0;
  await assert.rejects(
    collectPickedImage(
      async (maximum) => {
        const chunk = jpeg(maximum < 3 ? 3 : maximum).subarray(0, maximum);
        chunks.push(chunk);
        readBytes += chunk.length;
        return chunk;
      },
      active,
      [],
    ),
    failure("media_too_large"),
  );
  assert.equal(readBytes, ORIGINAL_BYTES + 1);
  assert(chunks.every((chunk) => chunk.every((byte) => byte === 0)));
  let calls = 0;
  await assert.rejects(
    collectPickedImage(
      async () => (++calls === 1 ? jpeg(12) : new Uint8Array()),
      active,
      [13],
    ),
    failure("media_unsupported"),
  );
});

test("short reads preserve the bytes while wrong signatures, reader overflow and scope closure fail closed", async () => {
  const original = jpeg(21);
  let offset = 0;
  const picked = await collectPickedImage(
    async () => {
      const chunk = original.slice(offset, offset + 3);
      offset += chunk.length;
      return chunk;
    },
    active,
    [21],
  );
  assert.deepEqual(picked.bytes, original);
  let calls = 0;
  await assert.rejects(
    collectPickedImage(
      async () => (++calls === 1 ? jpeg(12) : new Uint8Array()),
      active,
      [12],
      "image/png",
    ),
    failure("media_unsupported"),
  );
  await assert.rejects(
    collectPickedImage(async (maximum) => jpeg(maximum + 1), active, []),
    failure("media_too_large"),
  );
  let closed = false;
  const chunk = jpeg(12);
  await assert.rejects(
    collectPickedImage(
      async () => {
        closed = true;
        return chunk;
      },
      () => {
        if (closed) throw new Error("closed");
      },
      [],
    ),
    /closed/,
  );
  assert(chunk.every((byte) => byte === 0));
});

/** A DOM port model; tests never open an actual chooser or request OS permission. */
function browser() {
  class FakeInput extends EventTarget {
    type = "";
    accept = "";
    multiple = true;
    style = { display: "" };
    files: File[] | null = null;
    removed = false;
    clicks = 0;
    click() {
      this.clicks++;
    }
    remove() {
      this.removed = true;
    }
  }
  const previousDocument = Object.getOwnPropertyDescriptor(
    globalThis,
    "document",
  );
  const previousWindow = Object.getOwnPropertyDescriptor(globalThis, "window");
  const inputs: FakeInput[] = [];
  const window = new EventTarget();
  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: window,
  });
  Object.defineProperty(globalThis, "document", {
    configurable: true,
    value: {
      createElement: (tag: string) => {
        assert.equal(tag, "input");
        const input = new FakeInput();
        inputs.push(input);
        return input;
      },
      body: { appendChild: () => {} },
    },
  });
  const lifetime = new HostLifetime({
    endpoint: "https://example.test/v1",
    projectId: "project",
    accountId: "alice",
    appId: "app",
  });
  const ports = createPrivateMediaPorts(lifetime);
  return {
    inputs,
    ports,
    lifetime,
    close() {
      ports.dispose();
      lifetime.dispose();
      if (previousDocument)
        Object.defineProperty(globalThis, "document", previousDocument);
      else Reflect.deleteProperty(globalThis, "document");
      if (previousWindow)
        Object.defineProperty(globalThis, "window", previousWindow);
      else Reflect.deleteProperty(globalThis, "window");
    },
  };
}

test("Web chooser is image-only, rejects oversized opaque files before slice/decode and removes its input", async () => {
  const b = browser();
  try {
    const task = b.ports.pick();
    const input = b.inputs[0];
    let reads = 0;
    assert.equal(input.accept, "image/jpeg,image/png,image/webp");
    assert.equal(input.multiple, false);
    assert.equal(input.clicks, 1);
    input.files = [
      {
        size: ORIGINAL_BYTES + 1,
        type: "image/jpeg",
        slice: () => {
          reads++;
          throw new Error("must not read");
        },
      } as unknown as File,
    ];
    input.dispatchEvent(new Event("change"));
    await assert.rejects(task, failure("media_too_large"));
    assert.equal(reads, 0);
    assert(input.removed);
  } finally {
    b.close();
  }
});

test("Web chooser slices an opaque file in bounds without original object URLs and supports cancellation", async () => {
  const b = browser();
  try {
    const original = jpeg(CHUNK_BYTES + 5);
    const slices: number[] = [];
    const task = b.ports.pick();
    const input = b.inputs[0];
    input.files = [
      {
        size: original.length,
        type: "image/jpeg",
        slice: (start: number, end: number) => {
          slices.push(end - start);
          return { arrayBuffer: async () => original.slice(start, end).buffer };
        },
      } as unknown as File,
    ];
    input.dispatchEvent(new Event("change"));
    assert.deepEqual((await task)?.bytes, original);
    assert(slices.every((bytes) => bytes <= CHUNK_BYTES));
    assert.equal(slices.length, 2);
    assert(input.removed);
    const cancelled = b.ports.pick();
    b.inputs[1].dispatchEvent(new Event("cancel"));
    assert.equal(await cancelled, null);
    assert(b.inputs[1].removed);
    const abandoned = b.ports.pick();
    b.ports.dispose();
    await assert.rejects(abandoned, failure("disposed"));
    assert(b.inputs[2].removed);
  } finally {
    b.close();
  }
});
