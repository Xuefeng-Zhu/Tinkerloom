import assert from "node:assert/strict";
import test from "node:test";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { fullTemplates } from "./catalog";
import { FullAppController } from "./FullAppController";
import { InspectorFlushQueue } from "./inspectorSelection";
import {
  InspectorInputRegistry,
  InspectorTextDraft,
} from "./inspectorTextDraft";
import type { AppSpec } from "../spec/types";

const spec = fullTemplates.find((item) => item.id === "planner")!.spec;
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
function deferred<T = unknown>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
function fixture() {
  let current: Record<string, unknown> = app(spec),
    phase = "normal",
    ids = 0;
  const saved = new Map<string, string>(),
    requests: Record<string, unknown>[] = [];
  let gate: ReturnType<typeof deferred> | null = null;
  const controller = new FullAppController({
    scope,
    host: hostStores(new HostLifetime(scope), {
      async read(key) {
        return saved.get(key) ?? null;
      },
      async change(key, update) {
        const next = update(saved.get(key) ?? null);
        if (next === null) saved.delete(key);
        else saved.set(key, next);
      },
    }),
    newId: () => `operation_${++ids}`,
    transport: async (request) => {
      requests.push(request);
      if (request.op === "spec.getApp") {
        if (phase === "refresh_fail") throw new Error("refresh failed");
        return { app: current };
      }
      if (request.op === "spec.capabilities")
        return {
          apiVersion: 1,
          formatVersions: [1],
          generation: false,
          guidance: false,
          effects: [],
          privateMedia: false,
        };
      if (request.op === "spec.review") return gate!.promise;
      if (phase === "lost") throw new Error("lost response");
      if (gate) await gate.promise;
      if (request.op === "spec.saveDraft") {
        current = app(
          request.spec as AppSpec,
          Number(request.expectedRevision) + 1,
        );
        if (phase === "save_then_refresh_fail") phase = "refresh_fail";
      }
      return { app: current };
    },
  });
  return {
    controller,
    requests,
    saved,
    setPhase: (value: string) => {
      phase = value;
    },
    setGate: (value: ReturnType<typeof deferred> | null) => {
      gate = value;
    },
    setApp: (value: Record<string, unknown>) => {
      current = value;
    },
    get ids() {
      return ids;
    },
  };
}
function app(candidate: AppSpec, revision = 1) {
  return {
    id: "app",
    workspaceId: "workspace",
    name: candidate.name,
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: { editDefinition: true },
    controlRevision: 1,
    allowedActions: [],
    version: null,
    draft: {
      revision,
      baseVersionId: null,
      candidateHash: `hash_${revision}`,
      spec: candidate,
      publishedVersionId: null,
    },
    generation: null,
  };
}
function control(f: ReturnType<typeof fixture>) {
  const input = new InspectorTextDraft(
    spec.name,
    "app:name",
    f.controller.getSnapshot().editorResetEpoch,
  );
  const inputs = new InspectorInputRegistry();
  inputs.register(input);
  const unregister = f.controller.registerEditorInputGuard(
    inputs.canFlush,
    inputs.subscribe,
  );
  const sync = () =>
    input.configure(
      f.controller.getSnapshot().candidate?.name ?? "",
      "app:name",
      f.controller.getSnapshot().editorResetEpoch,
    );
  const unsubscribe = f.controller.subscribe(sync);
  function type(value: string) {
    input.change(value, false);
    try {
      f.controller.edit(
        { type: "RenameLabel", targetId: "app", label: value },
        true,
      );
      input.accept();
    } catch {
      input.reject();
    }
  }
  return {
    input,
    inputs,
    type,
    close() {
      unsubscribe();
      unregister();
      input.dispose();
    },
  };
}

test("blank semantic label remains visible through blur/refocus and can be repaired without losing the actual invalid text", async () => {
  const f = fixture();
  await f.controller.load();
  const c = control(f),
    epoch = f.controller.getSnapshot().editorResetEpoch;
  c.input.focus();
  c.type("");
  assert.ok(f.controller.getSnapshot().editorError);
  assert.equal(await c.input.blur(() => f.controller.flush()), false);
  c.input.focus();
  assert.equal(c.input.getSnapshot(), "");
  assert.equal(f.controller.getSnapshot().candidate?.name, spec.name);
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch);
  c.type("Repaired planner");
  assert.equal(await c.input.blur(() => f.controller.flush()), true);
  assert.equal(c.input.getSnapshot(), "Repaired planner");
  assert.equal(
    f.controller.getSnapshot().app?.draft?.spec.name,
    "Repaired planner",
  );
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch);
  assert.equal(f.requests.filter((r) => r.op === "spec.saveDraft").length, 1);
  c.close();
  f.controller.dispose();
});

test("a different valid control cannot mask a rejected raw input or trigger a save before repair/discard", async () => {
  const f = fixture();
  await f.controller.load();
  const c = control(f);
  c.type("");
  f.controller.edit({ type: "SetTheme", theme: "rose" });
  assert.equal(f.controller.getSnapshot().editorError, null);
  assert.equal(c.inputs.canFlush(), false);
  assert.equal(f.controller.hasRejectedEditorInput, true);
  assert.equal(f.controller.canLeave, false);
  assert.equal(await f.controller.flush(), false);
  assert.equal(f.requests.filter((r) => r.op === "spec.saveDraft").length, 0);
  f.controller.discardLocalEdits();
  assert.equal(c.input.getSnapshot(), spec.name);
  assert.equal(c.inputs.canFlush(), true);
  assert.equal(f.controller.hasRejectedEditorInput, false);
  assert.equal(await f.controller.flush(), true);
  c.close();
  f.controller.dispose();
});

test("unknown save keeps raw input, original retained payload and locks; flush never replays it", async () => {
  const f = fixture();
  await f.controller.load();
  const c = control(f);
  f.setPhase("lost");
  c.type("Original saved intent");
  assert.equal(await c.input.blur(() => f.controller.flush()), false);
  c.input.focus();
  assert.equal(c.input.getSnapshot(), "Original saved intent");
  assert.equal(f.controller.getSnapshot().pendingStatus, "uncertain");
  c.type("A later keystroke");
  assert.equal(c.input.getSnapshot(), "A later keystroke");
  assert.equal(c.inputs.canFlush(), false);
  assert.equal(await f.controller.flush(), false);
  const writes = f.requests.filter((r) => r.op === "spec.saveDraft");
  assert.equal(writes.length, 1);
  assert.equal((writes[0].spec as AppSpec).name, "Original saved intent");
  assert.equal(f.ids, 1);
  assert.ok(
    [...f.saved.values()].some((value) =>
      value.includes("Original saved intent"),
    ),
  );
  assert.throws(() => f.controller.discardLocalEdits(), /retained operation/);
  assert.equal(c.input.getSnapshot(), "A later keystroke");
  c.close();
  f.controller.dispose();
});

for (const newer of ["focus", "typing"] as const) {
  test(`late successful blur cannot erase newer ${newer}`, async () => {
    const input = new InspectorTextDraft("Saved", "app:name", 0),
      gate = deferred<boolean>();
    input.focus();
    input.change("First input");
    const pending = input.blur(() => gate.promise);
    input.focus();
    if (newer === "typing") input.change("New input");
    gate.resolve(true);
    assert.equal(await pending, false);
    assert.equal(
      input.getSnapshot(),
      newer === "typing" ? "New input" : "First input",
    );
    input.configure("Older saved value", "app:name", 0);
    assert.equal(
      input.getSnapshot(),
      newer === "typing" ? "New input" : "First input",
    );
    input.dispose();
  });
}

test("failed or thrown flush never erases rejected text even when an older parent value is supplied", async () => {
  for (const rejects of [false, true]) {
    const input = new InspectorTextDraft("Saved", "view:view_one:label", 0);
    input.change("Invalid local text");
    input.reject();
    assert.equal(
      await input.blur(async () => {
        if (rejects) throw new Error("save failed");
        return false;
      }),
      false,
    );
    input.configure("Saved", "view:view_one:label", 0);
    input.focus();
    assert.equal(input.getSnapshot(), "Invalid local text");
    assert.equal(await input.blur(async () => true), false);
    assert.equal(input.getSnapshot(), "Invalid local text");
    input.dispose();
  }
});

test("explicit reset and target identity fence old blur results while retaining new target text", async () => {
  for (const reset of ["epoch", "target"] as const) {
    const input = new InspectorTextDraft("First saved", "view:first:label", 0),
      gate = deferred<boolean>();
    input.change("Old raw text");
    const pending = input.blur(() => gate.promise);
    const identity =
      reset === "target" ? "view:second:label" : "view:first:label";
    input.configure(
      "Authoritative replacement",
      identity,
      reset === "epoch" ? 1 : 0,
    );
    assert.equal(input.getSnapshot(), "Authoritative replacement");
    input.change("New local text");
    gate.resolve(true);
    assert.equal(await pending, false);
    assert.equal(input.getSnapshot(), "New local text");
    input.dispose();
  }
});

test("unmount releases private raw text and StrictMode activation never accepts an old completion", async () => {
  const input = new InspectorTextDraft("Saved", "app:name", 0),
    gate = deferred<boolean>();
  let emissions = 0;
  input.subscribe(() => emissions++);
  input.change("Private old raw input");
  const pending = input.blur(() => gate.promise);
  input.dispose();
  assert.equal(input.getSnapshot(), "");
  input.configure("Cannot resurrect while closed", "app:name", 0);
  assert.equal(input.getSnapshot(), "");
  input.activate();
  input.configure("Fresh instance value", "app:name", 0);
  input.change("Fresh raw input");
  const before = emissions;
  gate.resolve(true);
  assert.equal(await pending, false);
  assert.equal(input.getSnapshot(), "Fresh raw input");
  assert.equal(emissions, before);
  input.dispose();
});

test("matching successful flush can show the authoritative canonical value without replacing subsequent edits", async () => {
  const input = new InspectorTextDraft("Saved", "app:name", 0),
    gate = deferred<boolean>();
  input.change("  Accepted input  ");
  const pending = input.blur(() => gate.promise);
  input.configure("Accepted input", "app:name", 0);
  assert.equal(input.getSnapshot(), "  Accepted input  ");
  gate.resolve(true);
  assert.equal(await pending, true);
  assert.equal(input.getSnapshot(), "Accepted input");
  input.dispose();
});

test("an autosave and blur/inspector selection join one controller save, with no extra operation ID", async () => {
  const f = fixture();
  await f.controller.load();
  const c = control(f),
    gate = deferred();
  f.setGate(gate);
  c.type("Joined save");
  const saving = f.controller.save();
  const queue = new InspectorFlushQueue({
    flush: () => f.controller.flush(),
    spec: () => f.controller.getSnapshot().candidate!,
    available: () => true,
    select() {},
  });
  const blur = c.input.blur(() => queue.flush());
  const selection = queue.inspect({ kind: "app" });
  await new Promise((done) => setTimeout(done, 0));
  assert.equal(f.requests.filter((r) => r.op === "spec.saveDraft").length, 1);
  assert.equal(f.ids, 1);
  gate.resolve({});
  await saving;
  assert.equal(await blur, true);
  assert.equal(await selection, true);
  assert.equal(c.input.getSnapshot(), "Joined save");
  assert.equal(f.requests.filter((r) => r.op === "spec.saveDraft").length, 1);
  queue.dispose();
  c.close();
  f.controller.dispose();
});

test("flush returns false promptly for an unrelated publication review instead of joining or repeating it", async () => {
  const f = fixture();
  await f.controller.load();
  const gate = deferred();
  f.setGate(gate);
  const reviewing = f.controller.review();
  await new Promise((done) => setTimeout(done, 0));
  assert.equal(f.controller.getSnapshot().busy, true);
  assert.equal(await f.controller.flush(), false);
  assert.equal(f.requests.filter((r) => r.op === "spec.review").length, 1);
  gate.resolve({
    review: {
      candidateHash: "hash_1",
      expectedRevision: 1,
      baseVersionId: null,
      currentVersionId: null,
      reviewHash: "review",
      changes: [],
      compatibilityErrors: [],
      enabledRuleIds: [],
      activateExistingRecordIds: [],
    },
  });
  await reviewing;
  assert.equal(f.controller.getSnapshot().review?.reviewHash, "review");
  f.controller.dispose();
});

test("confirmed save receipt followed by failed authority refresh is not a successful flush", async () => {
  const f = fixture();
  await f.controller.load();
  const c = control(f);
  f.setPhase("save_then_refresh_fail");
  c.type("Saved but not refreshed");
  assert.equal(await c.input.blur(() => f.controller.flush()), false);
  assert.equal(f.controller.getSnapshot().pending, null);
  assert.equal(f.controller.getSnapshot().refreshRequired, true);
  c.input.focus();
  assert.equal(c.input.getSnapshot(), "Saved but not refreshed");
  assert.equal(await f.controller.flush(), false);
  assert.equal(f.requests.filter((r) => r.op === "spec.saveDraft").length, 1);
  c.close();
  f.controller.dispose();
});

test("only explicit discard/replacement or clean authoritative content changes reset the editor epoch", async () => {
  const f = fixture();
  await f.controller.load();
  const c = control(f);
  const epoch = f.controller.getSnapshot().editorResetEpoch;
  c.type("First dirty name");
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch);
  c.type("");
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch);
  f.controller.discardLocalEdits();
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch + 1);
  assert.equal(c.input.getSnapshot(), spec.name);
  c.type("Valid new name");
  await f.controller.save();
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch + 1);
  const next = { ...spec, name: "Authoritative new name" };
  f.setApp(app(next, 3));
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch + 2);
  assert.equal(c.input.getSnapshot(), "Authoritative new name");
  f.setApp(app(next, 4));
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch + 2);
  f.controller.setCandidate(next);
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch + 3);
  c.close();
  f.controller.dispose();
});

test("invalid local raw input survives a background definition change until explicit discard", async () => {
  const f = fixture();
  await f.controller.load();
  const c = control(f);
  const epoch = f.controller.getSnapshot().editorResetEpoch;
  c.type("");
  f.setApp(app({ ...spec, name: "Remote name" }, 2));
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch);
  assert.equal(c.input.getSnapshot(), "");
  assert.equal(await f.controller.flush(), false);
  f.controller.discardLocalEdits();
  assert.equal(c.input.getSnapshot(), "Remote name");
  c.close();
  f.controller.dispose();
});

test("disposed account rejects late save/flush completion and keeps the encrypted unknown command", async () => {
  const f = fixture();
  await f.controller.load();
  const c = control(f),
    gate = deferred();
  f.setGate(gate);
  c.type("Private saving label");
  const pending = f.controller.flush();
  await new Promise((done) => setTimeout(done, 0));
  c.close();
  f.controller.dispose();
  gate.resolve({});
  assert.equal(await pending, false);
  assert.equal(f.controller.getSnapshot().app, null);
  assert.ok(f.saved.size > 0);
  assert.equal(c.input.getSnapshot(), "");
  const unregister = f.controller.registerEditorInputGuard(() => false);
  assert.equal(f.controller.hasRejectedEditorInput, false);
  unregister();
});

test("mounted input guard cleanup cannot clear another rejected input or leak its text", () => {
  const registry = new InspectorInputRegistry(),
    first = new InspectorTextDraft("One", "one", 0),
    second = new InspectorTextDraft("Two", "two", 0);
  const removeFirst = registry.register(first),
    removeSecond = registry.register(second);
  first.change("Private one");
  first.reject();
  second.change("Private two");
  second.reject();
  assert.equal(registry.canFlush(), false);
  removeFirst();
  assert.equal(registry.canFlush(), false);
  second.configure("Saved two", "two", 1);
  assert.equal(registry.canFlush(), true);
  removeSecond();
  first.dispose();
  second.dispose();
  assert.equal(registry.canFlush(), true);
});

test("raw guard transitions notify controller subscribers so route protection updates without raw text in state", async () => {
  const f = fixture();
  await f.controller.load();
  const c = control(f);
  const blocked: boolean[] = [];
  const unsubscribe = f.controller.subscribe(() =>
    blocked.push(f.controller.hasRejectedEditorInput),
  );
  c.input.change("Unvalidated input", false);
  assert.equal(blocked.at(-1), true);
  assert.equal(f.controller.getSnapshot().editorError, null);
  assert.equal(
    JSON.stringify(f.controller.getSnapshot()).includes("Unvalidated input"),
    false,
  );
  c.input.reject();
  c.input.change("Still not accepted", false);
  assert.equal(blocked.at(-1), true);
  c.input.accept();
  assert.equal(blocked.at(-1), false);
  assert.deepEqual(blocked, [true, false]);
  c.input.change("Rejected before discard", false);
  c.input.reject();
  f.controller.discardLocalEdits();
  assert.equal(blocked.at(-1), false);
  unsubscribe();
  c.close();
  f.controller.dispose();
});
