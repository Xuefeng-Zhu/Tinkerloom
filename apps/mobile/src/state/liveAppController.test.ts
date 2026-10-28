import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import type {
  AppBackend,
  AppDocument,
  LiveRecord,
  SaveDraft,
  SaveRecord,
} from "../backend/types";
import type { Definition } from "../preview/model";
import { LiveAppController, LiveAppRegistry } from "./liveAppController";

const definition: Definition = {
  title: "Notes",
  description: "",
  primaryFieldId: "title",
  fields: [{ id: "title", label: "Title", kind: "text", required: true }],
};
const document = (): AppDocument => ({
  id: "app",
  name: "Notes",
  workspaceId: "workspace",
  draftRevision: 1,
  publishedRevision: 1,
  definition,
  publishedDefinition: definition,
});
function scenario() {
  let ids = 0;
  let app = document();
  const records: LiveRecord[] = [];
  const commands: SaveRecord[] = [];
  const drafts: SaveDraft[] = [];
  let failRecord = false;
  let failRead: unknown;
  const backend: AppBackend = {
    newId: () => `id-${++ids}`,
    currentUser: async () => null,
    signIn: async () => {
      throw new Error("Unused");
    },
    signUp: async () => {
      throw new Error("Unused");
    },
    signOut: async () => {},
    listWorkspaces: async () => [],
    createWorkspace: async () => {},
    listApps: async () => [],
    createApp: async () => {},
    getApp: async () => {
      if (failRead) throw failRead;
      return app;
    },
    saveDraft: async (command) => {
      drafts.push(command);
      app = {
        ...app,
        draftRevision: command.expectedRevision + 1,
        definition: command.definition,
      };
      return app;
    },
    publishApp: async (command) => {
      app = {
        ...app,
        publishedRevision: command.expectedRevision,
        publishedDefinition: app.definition,
      };
      return app;
    },
    listRecords: async () => ({
      records: [...records],
      definitionRevision: app.publishedRevision,
      nextCursor: null,
    }),
    saveRecord: async (command) => {
      commands.push(command);
      if (failRecord)
        throw new BackendError(
          "Retry same save.",
          "transaction_conflict",
          "service",
          true,
          409,
        );
      const record = {
        id: command.id,
        revision: command.expectedRevision + 1,
        values: command.values,
      };
      records.push(record);
      return record;
    },
  };
  return {
    backend,
    commands,
    drafts,
    ids: () => ids,
    setApp: (value: AppDocument) => {
      app = value;
    },
    failRecord: (value: boolean) => {
      failRecord = value;
    },
    failRead: (value: unknown) => {
      failRead = value;
    },
  };
}

test("an unknown live record save retains original values, IDs and published version even after refresh", async () => {
  const s = scenario();
  const controller = new LiveAppController(s.backend, "app", () => {});
  await controller.load();
  s.failRecord(true);
  const values = { title: "Original" };
  await controller.writeRecord(null, values);
  values.title = "Mutated outside the controller";
  const original = {
    appId: "app",
    id: "id-1",
    operationId: "id-2",
    expectedRevision: 0,
    definitionRevision: 1,
    values: { title: "Original" },
  };
  assert.deepEqual(controller.getSnapshot().pending?.command, original);
  s.setApp({ ...document(), draftRevision: 2, publishedRevision: 2 });
  await controller.load();
  s.failRecord(false);
  await controller.retry();
  assert.deepEqual(s.commands, [original, original]);
  assert.equal(s.ids(), 2);
  assert.equal(controller.getSnapshot().pending, null);
});

test("refreshing a server draft never advances the expected revision of unsaved local edits", async () => {
  const s = scenario();
  const controller = new LiveAppController(s.backend, "app", () => {});
  await controller.load();
  controller.editDefinition({ ...definition, title: "Local edit" });
  s.setApp({ ...document(), draftRevision: 7 });
  await controller.load();
  assert.equal(controller.getSnapshot().editingRevision, 1);
  assert.equal(controller.getSnapshot().editingDefinition?.title, "Local edit");
  await controller.saveDefinition(controller.getSnapshot().editingDefinition!);
  assert.equal(s.drafts[0].expectedRevision, 1);
});

test("the reviewed publication uses its captured revision rather than a newer unreviewed draft", async () => {
  const s = scenario();
  const controller = new LiveAppController(s.backend, "app", () => {});
  await controller.load();
  let captured = 0;
  s.backend.publishApp = async (command) => {
    captured = command.expectedRevision;
    return document();
  };
  s.setApp({ ...document(), draftRevision: 5 });
  await controller.load();
  await controller.publish(1);
  assert.equal(captured, 1);
});

test("account-scoped registry disposal fences late private app responses", async () => {
  const s = scenario();
  let resolve!: (app: AppDocument) => void;
  s.backend.getApp = () =>
    new Promise((accept) => {
      resolve = accept;
    });
  const registry = new LiveAppRegistry(s.backend, () => {});
  const old = registry.get("first-account", "app");
  const loading = old.load();
  registry.keepUser("second-account");
  resolve(document());
  await loading;
  assert.equal(old.getSnapshot().app, null);
  assert.notEqual(registry.get("second-account", "app"), old);
});

test("live authorization failures clear displayed records and expire the account", async () => {
  const s = scenario();
  let expired = 0;
  const controller = new LiveAppController(s.backend, "app", () => {
    expired++;
  });
  await controller.load();
  s.failRead(
    new BackendError(
      "Expired",
      "unauthenticated",
      "unauthenticated",
      false,
      401,
    ),
  );
  await controller.load();
  assert.equal(expired, 1);
  assert.equal(controller.getSnapshot().app, null);
  assert.deepEqual(controller.getSnapshot().records, []);
});
