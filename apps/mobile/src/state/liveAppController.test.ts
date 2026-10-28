import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import type {
  AppBackend,
  AppDocument,
  LiveRecord,
  SaveDraft,
  SaveRecord,
  PublishApp,
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
  role: "owner",
  archived: false,
  candidateRevision: 1,
  basePublishedRevision: 1,
  capabilities: {
    editDefinition: true,
    share: true,
    writeRecords: true,
    archive: true,
    revokeAccess: true,
  },
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
    createInvitation: async () => {
      throw new Error("Unused");
    },
    acceptInvitation: async () => {
      throw new Error("Unused");
    },
    inspectInvitation: async () => {
      throw new Error("Unused");
    },
    listInvitations: async () => {
      throw new Error("Unused");
    },
    revokeInvitation: async () => {
      throw new Error("Unused");
    },
    listMembers: async () => {
      throw new Error("Unused");
    },
    setGrant: async () => {
      throw new Error("Unused");
    },
    archiveApp: async () => {
      throw new Error("Unused");
    },
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
        publishedRevision: command.candidateRevision,
        basePublishedRevision: command.candidateRevision,
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
  s.setApp({
    ...document(),
    draftRevision: 7,
    candidateRevision: 11,
    publishedRevision: 9,
  });
  await controller.load();
  assert.equal(controller.getSnapshot().editingRevision, 1);
  assert.equal(controller.getSnapshot().editingPublishedRevision, 1);
  assert.equal(controller.getSnapshot().editingDefinition?.title, "Local edit");
  await controller.saveDefinition(controller.getSnapshot().editingDefinition!);
  assert.equal(s.drafts[0].expectedRevision, 1);
  assert.equal(s.drafts[0].expectedPublishedRevision, 1);
});

test("the reviewed publication uses its captured revision rather than a newer unreviewed draft", async () => {
  const s = scenario();
  const controller = new LiveAppController(s.backend, "app", () => {});
  await controller.load();
  let captured: PublishApp | null = null;
  s.backend.publishApp = async (command) => {
    captured = command;
    return document();
  };
  const reviewed = {
    expectedRevision: 1,
    candidateRevision: 3,
    expectedPublishedRevision: 1,
  };
  s.setApp({
    ...document(),
    draftRevision: 5,
    candidateRevision: 10,
    publishedRevision: 7,
  });
  await controller.load();
  await controller.publish(reviewed);
  assert.deepEqual(captured, {
    appId: "app",
    operationId: "id-1",
    ...reviewed,
  });
});

test("an uncertain private draft retains the original counter, publication base, ID and content across refresh", async () => {
  const s = scenario();
  const commands: SaveDraft[] = [];
  s.backend.saveDraft = async (command) => {
    commands.push(command);
    throw new BackendError(
      "Unknown",
      "transaction_conflict",
      "service",
      true,
      409,
    );
  };
  const controller = new LiveAppController(s.backend, "app", () => {});
  await controller.load();
  const input = { ...definition, title: "Private edit" };
  controller.editDefinition(input);
  await controller.saveDefinition(input);
  input.title = "Changed outside";
  const original = JSON.stringify(controller.getSnapshot().pending);
  s.setApp({
    ...document(),
    draftRevision: 4,
    candidateRevision: 8,
    publishedRevision: 7,
  });
  await controller.load();
  await controller.retry();
  assert.equal(JSON.stringify(controller.getSnapshot().pending), original);
  assert.equal(commands.length, 2);
  assert.deepEqual(commands[0], commands[1]);
  assert.equal(commands[0].expectedPublishedRevision, 1);
  assert.equal(commands[0].definition.title, "Private edit");
  assert.equal(s.ids(), 1);
});

test("uncertain publication retries the exact reviewed tuple after a newer global publication", async () => {
  const s = scenario();
  const commands: PublishApp[] = [];
  s.backend.publishApp = async (command) => {
    commands.push(command);
    throw new BackendError(
      "Unknown",
      "transaction_conflict",
      "service",
      true,
      409,
    );
  };
  const controller = new LiveAppController(s.backend, "app", () => {});
  await controller.load();
  const review = {
    expectedRevision: 1,
    candidateRevision: 5,
    expectedPublishedRevision: 3,
  };
  await controller.publish(review);
  review.candidateRevision = 90;
  s.setApp({
    ...document(),
    draftRevision: 9,
    candidateRevision: 14,
    publishedRevision: 12,
  });
  await controller.load();
  assert.equal(commands.length, 1);
  await controller.retry();
  assert.deepEqual(commands[0], commands[1]);
  assert.equal(commands[1].candidateRevision, 5);
  assert.equal(commands[1].expectedPublishedRevision, 3);
  assert.equal(s.ids(), 1);
});

test("viewer/member/archived access cannot create commands and a downgrade clears retained editor content", async () => {
  const s = scenario();
  const controller = new LiveAppController(s.backend, "app", () => {});
  await controller.load();
  controller.editDefinition({ ...definition, title: "Private local draft" });
  assert.equal(
    controller.getSnapshot().editingDefinition?.title,
    "Private local draft",
  );
  for (const role of ["viewer", "member"] as const) {
    s.setApp({
      ...document(),
      role,
      draftRevision: 0,
      candidateRevision: 0,
      definition: null,
      capabilities: {
        editDefinition: false,
        share: false,
        writeRecords: false,
        archive: false,
        revokeAccess: false,
      },
    });
    await controller.load();
    assert.equal(controller.getSnapshot().editingDefinition, null);
    assert.equal(controller.getSnapshot().editingPublishedRevision, null);
    controller.editDefinition(definition);
    await controller.saveDefinition(definition);
    await controller.publish({
      expectedRevision: 1,
      candidateRevision: 1,
      expectedPublishedRevision: 1,
    });
    await controller.writeRecord(null, { title: "Blocked" });
  }
  s.setApp({
    ...document(),
    archived: true,
    capabilities: {
      editDefinition: false,
      share: false,
      writeRecords: false,
      archive: false,
      revokeAccess: true,
    },
  });
  await controller.load();
  await controller.saveDefinition(definition);
  await controller.writeRecord(null, { title: "Blocked" });
  assert.equal(s.ids(), 0);
  assert.equal(controller.getSnapshot().pending, null);
  assert.deepEqual(s.commands, []);
  assert.deepEqual(s.drafts, []);
});

test("legacy acknowledgment fields never grant permission to start a new live command", async () => {
  const s = scenario();
  const legacy = { ...document() };
  delete legacy.role;
  delete legacy.archived;
  delete legacy.capabilities;
  delete legacy.candidateRevision;
  delete legacy.basePublishedRevision;
  s.setApp(legacy);
  const controller = new LiveAppController(s.backend, "app", () => {});
  await controller.load();
  controller.editDefinition(definition);
  await controller.saveDefinition(definition);
  await controller.publish({
    expectedRevision: 1,
    candidateRevision: 1,
    expectedPublishedRevision: 1,
  });
  await controller.writeRecord(null, { title: "Blocked" });
  assert.equal(s.ids(), 0);
});

test("a confirmed downgrade clears the private editor even when its following record read fails", async () => {
  const s = scenario();
  const controller = new LiveAppController(s.backend, "app", () => {});
  await controller.load();
  controller.editDefinition({ ...definition, title: "Private local content" });
  s.setApp({
    ...document(),
    role: "viewer",
    draftRevision: 0,
    candidateRevision: 0,
    definition: null,
    capabilities: {
      editDefinition: false,
      share: false,
      writeRecords: false,
      archive: false,
      revokeAccess: false,
    },
  });
  s.backend.listRecords = async () => {
    throw new BackendError("Offline", "connection_failed", "transport");
  };
  await controller.load();
  assert.equal(controller.getSnapshot().app?.role, "viewer");
  assert.equal(controller.getSnapshot().app?.definition, null);
  assert.equal(controller.getSnapshot().editingDefinition, null);
  assert.equal(controller.getSnapshot().editingRevision, null);
  assert.deepEqual(controller.getSnapshot().records, []);
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
