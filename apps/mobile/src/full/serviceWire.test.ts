import assert from "node:assert/strict";
import test from "node:test";
import wire from "./fixtures/serviceWire.json";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import type { RuntimeAdapter } from "../runtime/types";
import { FunctionRuntimeAdapter } from "../runtime/functionAdapter";
import { FullAppController } from "./FullAppController";
import { FullWorkspaceController } from "./FullWorkspaceController";
import { manifest, platformCapabilities, publicationReview } from "./contracts";
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
function host() {
  const data = new Map<string, string>();
  return hostStores(new HostLifetime(scope), {
    async read(key) {
      return data.get(key) ?? null;
    },
    async change(key, update) {
      const next = update(data.get(key) ?? null);
      if (next === null) data.delete(key);
      else data.set(key, next);
    },
  });
}
test("real Dart shell, draft, review and published DTOs decode without invented capability aliases", () => {
  const shell = manifest(wire.shell.app, "app"),
    draft = manifest(wire.draft.app, "app"),
    published = manifest(wire.published.app, "app");
  assert.equal(shell.draft, null);
  assert.equal(shell.capabilities.editDefinition, true);
  assert.equal(shell.capabilities.build, undefined);
  assert.equal(draft.draft?.spec.name, "Reading Journal");
  assert.equal(
    publicationReview(wire.review.review).candidateHash,
    draft.draft?.candidateHash,
  );
  assert.equal(published.version?.hash, draft.draft?.candidateHash);
  assert.equal(platformCapabilities(wire.capabilities).generation, false);
});
test("full builder loads an actual Dart private draft and enables current editDefinition permission", async () => {
  const app = new FullAppController({
    scope,
    host: host(),
    newId: () => "operation",
    transport: async (request) =>
      request.op === "spec.capabilities" ? wire.capabilities : wire.draft,
  });
  await app.load();
  assert.equal(app.canBuild, true);
  assert.equal(app.getSnapshot().candidate?.name, "Reading Journal");
  assert.equal(app.getSnapshot().error, null);
  app.dispose();
});
test("a forged legacy build alias does not restore a missing editor permission", async () => {
  const response = structuredClone(wire.draft) as unknown as {
    app: Record<string, unknown>;
  };
  response.app.capabilities = { build: true };
  const app = new FullAppController({
    scope,
    host: host(),
    newId: () => "operation",
    transport: async (request) =>
      request.op === "spec.capabilities" ? wire.capabilities : response,
  });
  await app.load();
  assert.equal(app.canBuild, false);
  assert.equal(app.getSnapshot().candidate, null);
  app.dispose();
});
test("launcher and immutable history consume current Dart lifecycle DTOs", async () => {
  const controller = new FullWorkspaceController({
    scope,
    workspaceId: "ws",
    host: host(),
    newId: () => "operation",
    transport: async (request) => {
      switch (request.op) {
        case "spec.launcher":
          return wire.launcher;
        case "spec.listDrafts":
          return wire.drafts;
        case "spec.listVersions":
          return wire.versions;
        case "spec.getVersion":
          return wire.version;
        default:
          throw Error("Unexpected transport request");
      }
    },
  });
  await controller.load();
  assert.equal(controller.getSnapshot().error, null);
  assert.equal(
    controller.getSnapshot().apps[0].version?.name,
    "Reading Journal",
  );
  await controller.history("app");
  assert.equal(
    controller.getSnapshot().versions[0].id,
    wire.versions.versions[0].id,
  );
  await controller.inspectVersion("app", wire.versions.versions[0].id);
  assert.equal(
    controller.getSnapshot().historical?.spec.name,
    "Reading Journal",
  );
  assert.equal(controller.getSnapshot().error, null);
  controller.dispose();
});

test("new live runtimes receive negotiated operational capabilities", async () => {
  let observed = false;
  const controller = new FullAppController({
    scope,
    host: host(),
    newId: () => "operation",
    adapterFactory: (app, transport, context) => {
      assert.equal(context.platform?.generation, false);
      assert.deepEqual(context.platform?.effects, []);
      observed = true;
      return new FunctionRuntimeAdapter(app, transport);
    },
    transport: async (request) =>
      request.op === "spec.capabilities" ? wire.capabilities : wire.published,
  });
  await controller.load();
  assert.equal(observed, true);
  controller.dispose();
});
test("unrelated record changes preserve dirty forms and navigation; later publication stays visibly outdated across reloads", async () => {
  let response = structuredClone(wire.published);
  const controller = new FullAppController({
    scope,
    host: host(),
    newId: () => "operation",
    transport: async (request) =>
      request.op === "spec.capabilities" ? wire.capabilities : response,
  });
  await controller.load();
  const original = controller.runtime!;
  original.setDirty(true);
  response.app.controlRevision++;
  await controller.load();
  assert.equal(controller.runtime, original);
  assert.equal(original.getSnapshot().dirty, true);
  assert.equal(controller.getSnapshot().runtimeOutdated, false);
  response.app.version!.id = "new_version";
  await controller.load();
  assert.equal(controller.runtime, original);
  assert.equal(controller.getSnapshot().runtimeOutdated, true);
  await controller.load();
  assert.equal(controller.runtime, original);
  assert.equal(controller.getSnapshot().runtimeOutdated, true);
  controller.dispose();
});

test("a trusted role downgrade hides private candidates before a failed manifest refresh", async () => {
  let denyRead = false;
  const controller = new FullAppController({
    scope,
    host: host(),
    newId: () => "operation",
    transport: async (request) => {
      if (request.op === "spec.capabilities") return wire.capabilities;
      if (denyRead) throw new Error("Simulated interrupted authorized refresh");
      return wire.draft;
    },
  });
  await controller.load();
  assert.ok(controller.getSnapshot().candidate);
  denyRead = true;
  const refresh = controller.observeInvalidation({
    appId: "app",
    role: "viewer",
    archived: false,
    versionId: null,
    controlRevision: 3,
  });
  assert.equal(controller.getSnapshot().candidate, null);
  assert.equal(controller.getSnapshot().app, null);
  await refresh;
  assert.equal(controller.getSnapshot().candidate, null);
  assert.equal(controller.getSnapshot().app, null);
  controller.dispose();
});

test("focused route leases pause hidden screens without an old cleanup disabling the new route", async () => {
  const activity: boolean[] = [];
  const controller = new FullAppController({
    scope,
    host: host(),
    newId: () => "operation",
    transport: async (request) =>
      request.op === "spec.capabilities" ? wire.capabilities : wire.published,
    adapterFactory: (app, transport) => {
      const adapter: RuntimeAdapter = new FunctionRuntimeAdapter(
        app,
        transport,
      );
      adapter.setActive = (active) => {
        activity.push(active);
      };
      return adapter;
    },
  });
  const first = controller.acquireLiveLease(true);
  await controller.load();
  assert.equal(activity.at(-1), true);
  const next = controller.acquireLiveLease(true);
  first();
  assert.equal(activity.at(-1), true);
  next();
  assert.equal(activity.at(-1), false);
  const builder = controller.acquireLiveLease(false);
  assert.equal(activity.at(-1), false);
  builder();
  controller.dispose();
});
