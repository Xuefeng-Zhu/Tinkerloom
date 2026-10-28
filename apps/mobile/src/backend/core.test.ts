import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { AppwriteBackend, type ExecutionResult, type SdkAdapter } from "./core";
import { BackendError } from "./errors";
import { validatePublicConfig } from "./config";
import type { Definition } from "../preview/model";

const richContract = JSON.parse(
  readFileSync(
    new URL(
      "../../../../appwrite_backend/test/fixtures/rich_contract.json",
      import.meta.url,
    ),
    "utf8",
  ),
) as {
  validDefinitions: { name: string; input: Definition; expected: Definition }[];
  invalidDefinitions: { name: string; input: Definition }[];
};

const user = { $id: "owner", email: "owner@example.test", name: "Owner" };

function setup() {
  let nextAccount: unknown = user;
  let accountError: unknown;
  let nextExecution: ExecutionResult = {
    status: "completed",
    responseStatusCode: 200,
    responseBody: JSON.stringify({ workspaces: [] }),
  };
  let executionError: unknown;
  const requests: string[] = [];
  const sdk: SdkAdapter = {
    newId: () => "stable-id",
    account: {
      get: async () => {
        if (accountError) throw accountError;
        return nextAccount;
      },
      create: async () => user,
      createEmailPasswordSession: async () => ({}),
      deleteSession: async () => ({}),
    },
    execute: async (body) => {
      requests.push(body);
      if (executionError) throw executionError;
      return nextExecution;
    },
  };
  return {
    backend: new AppwriteBackend(sdk),
    requests,
    setAccount: (value: unknown) => {
      nextAccount = value;
    },
    failAccount: (error: unknown) => {
      accountError = error;
    },
    setExecution: (value: ExecutionResult) => {
      nextExecution = value;
    },
    failExecution: (error: unknown) => {
      executionError = error;
    },
    succeed: (body: unknown) => {
      executionError = undefined;
      nextExecution = {
        status: "completed",
        responseStatusCode: 200,
        responseBody: JSON.stringify(body),
      };
    },
  };
}

test("only an authentication failure clears the current session", async () => {
  const scenario = setup();
  assert.deepEqual(await scenario.backend.currentUser(), {
    id: "owner",
    email: user.email,
    name: user.name,
  });
  scenario.failAccount({ code: 401, type: "user_unauthorized" });
  assert.equal(await scenario.backend.currentUser(), null);
  scenario.failAccount(
    new TypeError("Network failure with private transport details"),
  );
  await assert.rejects(scenario.backend.currentUser(), (error: unknown) => {
    assert.ok(error instanceof BackendError);
    assert.equal(error.kind, "transport");
    assert.equal(error.message.includes("private"), false);
    return true;
  });
  scenario.failAccount({ code: 403, type: "user_blocked" });
  await assert.rejects(
    scenario.backend.currentUser(),
    (error: unknown) =>
      error instanceof BackendError && error.kind === "service",
  );
});

test("unknown mutation outcome retains an exact caller-owned command on retry", async () => {
  const scenario = setup();
  const command = { id: "stable-id", name: "Volunteer shifts" };
  scenario.failExecution(new TypeError("Connection lost"));
  await assert.rejects(
    scenario.backend.createWorkspace(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  scenario.succeed({ workspace: command });
  await scenario.backend.createWorkspace(command);
  assert.equal(scenario.requests[0], scenario.requests[1]);
  assert.deepEqual(JSON.parse(scenario.requests[0]), {
    op: "createWorkspace",
    ...command,
  });
});

test("duplicate and cross-workspace rows are rejected before being returned", async () => {
  const scenario = setup();
  scenario.succeed({
    workspaces: [
      { id: "a", name: "A", role: "owner" },
      { id: "a", name: "B", role: "owner" },
    ],
  });
  await assert.rejects(
    scenario.backend.listWorkspaces(),
    (error: unknown) =>
      error instanceof BackendError && error.kind === "invalid_response",
  );
  scenario.succeed({
    apps: [
      {
        id: "a",
        name: "Private app",
        workspaceId: "another-workspace",
        role: "owner",
        archived: false,
        capabilities: {
          editDefinition: true,
          share: true,
          writeRecords: true,
          archive: true,
          revokeAccess: true,
        },
      },
    ],
  });
  await assert.rejects(
    scenario.backend.listApps("my-workspace"),
    (error: unknown) =>
      error instanceof BackendError && error.kind === "invalid_response",
  );
});

test("an incomplete or malformed success cannot be promoted to a confirmed write", async () => {
  const scenario = setup();
  const command = { id: "stable-id", name: "Notes" };
  scenario.setExecution({
    status: "processing",
    responseStatusCode: 0,
    responseBody: "",
  });
  await assert.rejects(
    scenario.backend.createWorkspace(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  scenario.setExecution({
    status: "completed",
    responseStatusCode: 200,
    responseBody: "<html>gateway</html>",
  });
  await assert.rejects(
    scenario.backend.createWorkspace(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  scenario.setExecution({
    status: "completed",
    responseStatusCode: 0,
    responseBody: "{}",
  });
  await assert.rejects(
    scenario.backend.createWorkspace(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  scenario.succeed({ workspace: { ...command, id: "wrong-id" } });
  await assert.rejects(
    scenario.backend.createWorkspace(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
});

test("function errors preserve safe codes and distinguish expired auth from conflicts", async () => {
  const scenario = setup();
  scenario.setExecution({
    status: "completed",
    responseStatusCode: 401,
    responseBody: JSON.stringify({ error: "unauthenticated" }),
  });
  await assert.rejects(
    scenario.backend.listWorkspaces(),
    (error: unknown) =>
      error instanceof BackendError && error.kind === "unauthenticated",
  );
  scenario.setExecution({
    status: "completed",
    responseStatusCode: 409,
    responseBody: JSON.stringify({ error: "id_conflict" }),
  });
  await assert.rejects(
    scenario.backend.createWorkspace({ id: "stable-id", name: "Notes" }),
    (error: unknown) => {
      assert.ok(error instanceof BackendError);
      assert.equal(error.code, "id_conflict");
      assert.equal(error.uncertain, false);
      return true;
    },
  );
});

test("public configuration rejects credentials and insecure remote endpoints", () => {
  const base = {
    endpoint: "https://sfo.cloud.appwrite.io/v1",
    projectId: "project",
    functionId: "tinkerloom-core",
  };
  assert.equal(
    validatePublicConfig(base).config?.platformId,
    "com.tinkerloom.app",
  );
  assert.equal(
    validatePublicConfig({ ...base, endpoint: "http://remote.example/v1" })
      .config,
    null,
  );
  assert.equal(
    validatePublicConfig({
      ...base,
      endpoint: "https://user:secret@example.test/v1",
    }).config,
    null,
  );
  assert.equal(
    validatePublicConfig({
      ...base,
      endpoint: "https://example.test/v1?key=secret",
    }).config,
    null,
  );
  assert.equal(
    validatePublicConfig({ ...base, endpoint: "http://localhost/v1" }).issues
      .length,
    0,
  );
  assert.equal(validatePublicConfig({ ...base, functionId: "" }).config, null);
});

function authScenario() {
  const calls = { creates: 0, sessions: 0, reads: 0 };
  let create = async (): Promise<unknown> => user;
  let session = async (): Promise<unknown> => ({});
  let read = async (): Promise<unknown> => user;
  const sdk: SdkAdapter = {
    newId: () => "account-id",
    execute: async () => {
      throw new Error("Unexpected function call");
    },
    account: {
      create: async () => {
        calls.creates++;
        return create();
      },
      createEmailPasswordSession: async () => {
        calls.sessions++;
        return session();
      },
      get: async () => {
        calls.reads++;
        return read();
      },
      deleteSession: async () => ({}),
    },
  };
  return {
    backend: new AppwriteBackend(sdk),
    calls,
    onCreate: (action: () => Promise<unknown>) => {
      create = action;
    },
    onSession: (action: () => Promise<unknown>) => {
      session = action;
    },
    onRead: (action: () => Promise<unknown>) => {
      read = action;
    },
  };
}

test("a created session with a lost account-read response is reconciled once without another auth mutation", async () => {
  const scenario = authScenario();
  scenario.onRead(async () => {
    if (scenario.calls.reads === 1) throw new TypeError("Read response lost");
    return user;
  });
  const result = await scenario.backend.signIn(
    " OWNER@example.test ",
    "password",
  );
  assert.equal(result.id, user.$id);
  assert.deepEqual(scenario.calls, { creates: 0, sessions: 1, reads: 2 });
});

test("an existing session is accepted only when it matches the attempted email", async () => {
  const scenario = authScenario();
  scenario.onSession(async () => {
    throw { code: 401, type: "user_session_already_exists" };
  });
  assert.equal(
    (await scenario.backend.signIn(user.email, "password")).id,
    user.$id,
  );
  assert.deepEqual(scenario.calls, { creates: 0, sessions: 1, reads: 1 });

  await assert.rejects(
    scenario.backend.signIn("another@example.test", "password"),
    (error: unknown) => {
      assert.ok(error instanceof BackendError);
      assert.equal(error.code, "existing_session_mismatch");
      assert.equal(error.kind, "service");
      assert.match(error.message, /different account/i);
      return true;
    },
  );
  assert.deepEqual(scenario.calls, { creates: 0, sessions: 2, reads: 2 });
});

test("a lost session mutation response can recover the same user using only a read", async () => {
  const scenario = authScenario();
  scenario.onSession(async () => {
    throw new TypeError("Session response lost");
  });
  assert.equal(
    (await scenario.backend.signIn(user.email, "password")).id,
    user.$id,
  );
  assert.deepEqual(scenario.calls, { creates: 0, sessions: 1, reads: 1 });
});

test("unknown signup does not automatically repeat account creation or start a session", async () => {
  const scenario = authScenario();
  scenario.onCreate(async () => {
    throw new TypeError("Create response lost");
  });
  await assert.rejects(
    scenario.backend.signUp(user.email, "password", "Owner"),
    (error: unknown) => {
      assert.ok(error instanceof BackendError);
      assert.equal(error.uncertain, true);
      assert.match(error.message, /may already exist.*Sign in/);
      return true;
    },
  );
  assert.deepEqual(scenario.calls, { creates: 1, sessions: 0, reads: 0 });
});

test("signup conflict directs the caller to sign in without creating another account", async () => {
  const scenario = authScenario();
  scenario.onCreate(async () => {
    throw { code: 409, type: "user_already_exists" };
  });
  await assert.rejects(
    scenario.backend.signUp(user.email, "password", "Owner"),
    (error: unknown) => {
      assert.ok(error instanceof BackendError);
      assert.equal(error.code, "user_already_exists");
      assert.equal(error.uncertain, false);
      assert.match(error.message, /Sign in/);
      return true;
    },
  );
  assert.deepEqual(scenario.calls, { creates: 1, sessions: 0, reads: 0 });
});

test("failed signin reconciliation remains uncertain and never repeats the session mutation", async () => {
  const scenario = authScenario();
  scenario.onSession(async () => {
    throw new TypeError("Session response lost");
  });
  scenario.onRead(async () => {
    throw new TypeError("Reconciliation offline");
  });
  await assert.rejects(
    scenario.backend.signIn(user.email, "password"),
    (error: unknown) => {
      assert.ok(error instanceof BackendError);
      assert.equal(error.uncertain, true);
      assert.match(error.message, /Check your existing session/);
      return true;
    },
  );
  assert.deepEqual(scenario.calls, { creates: 0, sessions: 1, reads: 1 });
});

const definition = {
  title: "Notes",
  description: "A notebook",
  primaryFieldId: "title",
  fields: [
    { id: "title", label: "Title", kind: "text" as const, required: true },
  ],
};
const appDocument = {
  id: "app",
  workspaceId: "workspace",
  name: "Notebook",
  role: "owner",
  archived: false,
  capabilities: {
    editDefinition: true,
    share: true,
    writeRecords: true,
    archive: true,
    revokeAccess: true,
  },
  candidateRevision: 1,
  basePublishedRevision: 1,
  draftRevision: 1,
  publishedRevision: 1,
  definition,
  publishedDefinition: definition,
};

test("app documents and paginated records must match the requested app/version", async () => {
  const scenario = setup();
  scenario.succeed({ app: { ...appDocument, id: "other-app" } });
  await assert.rejects(
    scenario.backend.getApp("app"),
    (error: unknown) =>
      error instanceof BackendError && error.kind === "invalid_response",
  );
  scenario.succeed({ app: appDocument });
  assert.equal((await scenario.backend.getApp("app")).publishedRevision, 1);
  scenario.succeed({
    records: [{ id: "record", revision: 1, values: { title: "One" } }],
    definitionRevision: 2,
    nextCursor: null,
  });
  await assert.rejects(
    scenario.backend.listRecords("app", 1),
    (error: unknown) =>
      error instanceof BackendError && error.kind === "invalid_response",
  );
  scenario.succeed({
    records: [{ id: "record", revision: 1, values: { title: "One" } }],
    definitionRevision: 1,
    nextCursor: "unrelated",
  });
  await assert.rejects(
    scenario.backend.listRecords("app", 1),
    (error: unknown) =>
      error instanceof BackendError && error.kind === "invalid_response",
  );
});

test("a transaction conflict retains the original draft operation and input", async () => {
  const scenario = setup();
  const command = {
    appId: "app",
    operationId: "operation",
    expectedRevision: 0,
    expectedPublishedRevision: 0,
    definition,
  };
  scenario.setExecution({
    status: "completed",
    responseStatusCode: 409,
    responseBody: JSON.stringify({ error: "transaction_conflict" }),
  });
  await assert.rejects(
    scenario.backend.saveDraft(command),
    (error: unknown) =>
      error instanceof BackendError &&
      error.uncertain &&
      error.code === "transaction_conflict",
  );
  scenario.succeed({
    app: {
      ...appDocument,
      publishedRevision: 0,
      basePublishedRevision: 0,
      candidateRevision: 1,
      publishedDefinition: null,
    },
  });
  await scenario.backend.saveDraft(command);
  assert.equal(scenario.requests[0], scenario.requests[1]);
});

test("a mismatched record revision or receipt cannot become a confirmed save", async () => {
  const scenario = setup();
  const command = {
    appId: "app",
    id: "record",
    operationId: "save",
    expectedRevision: 2,
    definitionRevision: 1,
    values: { title: "Changed" },
  };
  scenario.succeed({
    record: { id: "record", revision: 2, values: command.values },
    definitionRevision: 1,
  });
  await assert.rejects(
    scenario.backend.saveRecord(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  scenario.succeed({
    record: { id: "record", revision: 3, values: command.values },
    definitionRevision: 2,
  });
  await assert.rejects(
    scenario.backend.saveRecord(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  scenario.succeed({
    record: { id: "record", revision: 3, values: command.values },
    definitionRevision: 1,
  });
  assert.equal((await scenario.backend.saveRecord(command)).revision, 3);
  scenario.succeed({
    record: { id: "record", revision: 3, values: { title: "Wrong content" } },
    definitionRevision: 1,
  });
  await assert.rejects(
    scenario.backend.saveRecord(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
});

test("oversized UTF-8 record content is rejected before a mutation is sent", async () => {
  const scenario = setup();
  const longText = "🌿".repeat(2000);
  await assert.rejects(
    scenario.backend.saveRecord({
      appId: "app",
      id: "record",
      operationId: "save",
      expectedRevision: 0,
      definitionRevision: 1,
      values: {
        title: "Large note",
        first: longText,
        second: longText,
        third: longText,
      },
    }),
    (error: unknown) =>
      error instanceof BackendError &&
      error.code === "content_too_large" &&
      !error.uncertain,
  );
  assert.equal(scenario.requests.length, 0);
});

test("shared definition fixtures retain canonical views and do not add a legacy default", async () => {
  for (const fixture of richContract.validDefinitions) {
    const scenario = setup();
    scenario.succeed({
      app: {
        ...appDocument,
        draftRevision: 1,
        publishedRevision: 0,
        basePublishedRevision: 0,
        candidateRevision: 1,
        publishedDefinition: null,
        definition: fixture.expected,
      },
    });
    const result = await scenario.backend.saveDraft({
      appId: "app",
      expectedRevision: 0,
      expectedPublishedRevision: 0,
      operationId: "rich-save",
      definition: fixture.input,
    });
    assert.deepEqual(
      result.definition?.view,
      fixture.expected.view,
      fixture.name,
    );
    assert.equal(
      Object.prototype.hasOwnProperty.call(result.definition, "view"),
      Object.prototype.hasOwnProperty.call(fixture.expected, "view"),
      fixture.name,
    );
    const submitted = JSON.parse(scenario.requests[0]) as {
      definition: Definition;
    };
    assert.equal(
      Object.prototype.hasOwnProperty.call(submitted.definition, "view"),
      Object.prototype.hasOwnProperty.call(fixture.input, "view"),
      fixture.name,
    );
  }
});

test("malformed or unknown view properties are rejected by the API response parser", async () => {
  const scenario = setup();
  for (const fixture of richContract.invalidDefinitions) {
    scenario.succeed({
      app: {
        ...appDocument,
        definition: fixture.input,
        publishedDefinition: fixture.input,
      },
    });
    await assert.rejects(
      scenario.backend.getApp("app"),
      (error: unknown) =>
        error instanceof BackendError && error.kind === "invalid_response",
      fixture.name,
    );
  }
  const agenda = richContract.validDefinitions.find(
    (fixture) => fixture.name === "agenda-with-optional-date",
  )!;
  scenario.succeed({
    app: {
      ...appDocument,
      draftRevision: 1,
      publishedRevision: 0,
      basePublishedRevision: 0,
      candidateRevision: 1,
      publishedDefinition: null,
      definition: { ...agenda.expected, view: { kind: "table" } },
    },
  });
  await assert.rejects(
    scenario.backend.saveDraft({
      appId: "app",
      expectedRevision: 0,
      expectedPublishedRevision: 0,
      operationId: "rich-save",
      definition: agenda.input,
    }),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
});

test("numeric response values preserve zero while nonfinite or out-of-range numbers are rejected", async () => {
  const scenario = setup();
  for (const amount of [0, 12.75, -0.125, 1e15, -1e15]) {
    scenario.succeed({
      records: [
        { id: "record", revision: 1, values: { title: "Ledger", amount } },
      ],
      definitionRevision: 1,
      nextCursor: null,
    });
    assert.equal(
      (await scenario.backend.listRecords("app", 1)).records[0].values.amount,
      amount,
    );
    scenario.succeed({
      record: {
        id: "record",
        revision: 1,
        values: { title: "Ledger", amount },
      },
      definitionRevision: 1,
    });
    assert.equal(
      (
        await scenario.backend.saveRecord({
          appId: "app",
          id: "record",
          expectedRevision: 0,
          operationId: "numeric-save",
          definitionRevision: 1,
          values: { title: "Ledger", amount },
        })
      ).values.amount,
      amount,
    );
  }
  for (const literal of [
    "1e309",
    "-1e309",
    "1000000000000001",
    "-1000000000000001",
    "null",
    "[]",
  ]) {
    scenario.setExecution({
      status: "completed",
      responseStatusCode: 200,
      responseBody: `{"records":[{"id":"record","revision":1,"values":{"title":"Ledger","amount":${literal}}}],"definitionRevision":1,"nextCursor":null}`,
    });
    await assert.rejects(
      scenario.backend.listRecords("app", 1),
      (error: unknown) =>
        error instanceof BackendError && error.kind === "invalid_response",
      literal,
    );
  }
});

test("nonfinite mutation values cannot be silently serialized to null", async () => {
  const scenario = setup();
  for (const amount of [
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.NEGATIVE_INFINITY,
    1e15 + 1,
    -1e15 - 1,
  ]) {
    await assert.rejects(
      scenario.backend.saveRecord({
        appId: "app",
        id: "record",
        expectedRevision: 0,
        operationId: "numeric-save",
        definitionRevision: 1,
        values: { title: "Ledger", amount },
      }),
      (error: unknown) =>
        error instanceof BackendError &&
        error.code === "invalid_values" &&
        !error.uncertain,
    );
  }
  assert.equal(scenario.requests.length, 0);
});

test("record replay accepts Dart-normalized NEL content while retaining exact raw command bytes", async () => {
  const scenario = setup();
  const command = {
    appId: "app",
    id: "record",
    expectedRevision: 0,
    operationId: "unicode-save",
    definitionRevision: 1,
    values: {
      title: "\u0085Title\u0085",
      body: "\u0085Line\u0085inside\u0085",
      category: "\u0085Blue\u0085",
      amount: 0,
      when: "2024-02-29",
    },
  };
  const expected = {
    title: "Title",
    body: "Line\u0085inside",
    category: "Blue",
    amount: 0,
    when: "2024-02-29",
  };
  const original = JSON.stringify(command);
  scenario.failExecution(new TypeError("Response lost after commit"));
  await assert.rejects(
    scenario.backend.saveRecord(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  scenario.succeed({
    record: { id: "record", revision: 1, values: expected },
    definitionRevision: 1,
  });
  assert.deepEqual(
    (await scenario.backend.saveRecord(command)).values,
    expected,
  );
  assert.deepEqual(
    (await scenario.backend.saveRecord(command)).values,
    expected,
  );
  assert.equal(scenario.requests[0], scenario.requests[1]);
  assert.equal(scenario.requests[1], scenario.requests[2]);
  assert.deepEqual(JSON.parse(scenario.requests[0]).values, command.values);
  assert.equal(JSON.stringify(command), original);
});

test("draft replay confirms canonical NEL title, labels, and choices without trimming description", async () => {
  const scenario = setup();
  const input: Definition = {
    title: "\u0085Notes\u0085",
    description: "\u0085Keep description\u0085",
    primaryFieldId: "title",
    fields: [
      {
        id: "title",
        label: "\u0085Heading\u0085",
        kind: "text",
        required: true,
      },
      {
        id: "category",
        label: "\u0085Category\u0085",
        kind: "choice",
        options: ["\u0085Blue\u0085", "Gold"],
      },
    ],
  };
  const expected: Definition = {
    ...input,
    title: "Notes",
    fields: [
      { id: "title", label: "Heading", kind: "text", required: true },
      {
        id: "category",
        label: "Category",
        kind: "choice",
        options: ["Blue", "Gold"],
      },
    ],
  };
  const command = {
    appId: "app",
    expectedRevision: 0,
    expectedPublishedRevision: 0,
    operationId: "unicode-draft",
    definition: input,
  };
  scenario.failExecution(new TypeError("Response lost after commit"));
  await assert.rejects(
    scenario.backend.saveDraft(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  scenario.succeed({
    app: {
      ...appDocument,
      draftRevision: 1,
      publishedRevision: 0,
      basePublishedRevision: 0,
      candidateRevision: 1,
      publishedDefinition: null,
      definition: expected,
    },
  });
  const result = await scenario.backend.saveDraft(command);
  assert.equal(result.definition?.title, "Notes");
  assert.equal(result.definition?.fields[0].label, "Heading");
  assert.deepEqual(result.definition?.fields[1].options, ["Blue", "Gold"]);
  assert.equal(result.definition?.description, input.description);
  assert.equal(scenario.requests[0], scenario.requests[1]);
  assert.deepEqual(JSON.parse(scenario.requests[0]).definition, input);
});

test("workspace and app names use the same canonical NEL trimming as the Function", async () => {
  const scenario = setup();
  scenario.succeed({ workspace: { id: "workspace", name: "Workbench" } });
  const workspaceCommand = { id: "workspace", name: "\u0085Workbench\u0085" };
  await scenario.backend.createWorkspace(workspaceCommand);
  assert.equal(JSON.parse(scenario.requests[0]).name, "Workbench");
  assert.equal(workspaceCommand.name, "\u0085Workbench\u0085");
  scenario.succeed({
    app: { id: "app", workspaceId: "workspace", name: "Notes" },
  });
  await scenario.backend.createApp({
    id: "app",
    workspaceId: "workspace",
    name: "\u0085Notes\u0085",
  });
  assert.equal(JSON.parse(scenario.requests[1]).name, "Notes");
});

test("private draft counters are independent from global candidates and published versions", async () => {
  const s = setup();
  const builder = {
    ...appDocument,
    role: "builder",
    draftRevision: 2,
    candidateRevision: 5,
    publishedRevision: 9,
    basePublishedRevision: 1,
    capabilities: {
      editDefinition: true,
      share: true,
      writeRecords: true,
      archive: false,
      revokeAccess: true,
    },
  };
  s.succeed({ app: builder });
  const result = await s.backend.getApp("app");
  assert.equal(result.draftRevision, 2);
  assert.equal(result.candidateRevision, 5);
  assert.equal(result.publishedRevision, 9);
  s.succeed({
    app: {
      ...builder,
      draftRevision: 0,
      candidateRevision: 0,
      basePublishedRevision: 9,
      definition: null,
    },
  });
  assert.equal((await s.backend.getApp("app")).definition, null);
});

test("ordinary reads reject missing access, inconsistent capabilities and leaked nonbuilder drafts", async () => {
  const s = setup();
  const legacy = { ...appDocument } as Record<string, unknown>;
  for (const key of [
    "role",
    "archived",
    "capabilities",
    "candidateRevision",
    "basePublishedRevision",
  ])
    delete legacy[key];
  for (const value of [
    legacy,
    { ...appDocument, capabilities: undefined },
    { ...appDocument, role: "viewer" },
    { ...appDocument, archived: true },
    { ...appDocument, candidateRevision: 0 },
    { ...appDocument, basePublishedRevision: 2 },
    { ...appDocument, publishedRevision: 2_147_483_647 },
    { ...appDocument, ownerPrivateDraft: definition },
  ]) {
    s.succeed({ app: value });
    await assert.rejects(
      s.backend.getApp("app"),
      (error: unknown) =>
        error instanceof BackendError && error.kind === "invalid_response",
    );
  }
  const readOnly = {
    ...appDocument,
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
  };
  s.succeed({ app: readOnly });
  assert.equal((await s.backend.getApp("app")).role, "viewer");
  s.succeed({
    app: { ...readOnly, draftRevision: 1, candidateRevision: 1, definition },
  });
  await assert.rejects(s.backend.getApp("app"));
});

test("workspace and app summaries require explicit access without carrying private definitions", async () => {
  const s = setup();
  s.succeed({
    workspaces: [{ id: "workspace", name: "Shared", role: "member" }],
  });
  assert.equal((await s.backend.listWorkspaces())[0].role, "member");
  s.succeed({ workspaces: [{ id: "workspace", name: "Shared" }] });
  await assert.rejects(s.backend.listWorkspaces());
  const { id, workspaceId, name, role, archived, capabilities } = appDocument;
  const summary = { id, workspaceId, name, role, archived, capabilities };
  s.succeed({ apps: [summary] });
  assert.equal(
    (await s.backend.listApps("workspace"))[0].capabilities?.share,
    true,
  );
  s.succeed({ apps: [{ ...summary, definition }] });
  await assert.rejects(s.backend.listApps("workspace"));
  s.succeed({ apps: [{ id, workspaceId, name }] });
  await assert.rejects(s.backend.listApps("workspace"));
});

test("draft receipts confirm their original publication base and a fresh global candidate", async () => {
  const s = setup();
  const command = {
    appId: "app",
    expectedRevision: 1,
    expectedPublishedRevision: 9,
    operationId: "private-draft",
    definition,
  };
  const saved = {
    ...appDocument,
    draftRevision: 2,
    publishedRevision: 9,
    candidateRevision: 12,
    basePublishedRevision: 9,
  };
  s.failExecution(new TypeError("Commit response lost"));
  await assert.rejects(
    s.backend.saveDraft(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  s.succeed({ app: saved });
  assert.equal((await s.backend.saveDraft(command)).candidateRevision, 12);
  assert.equal(s.requests[0], s.requests[1]);
  for (const overrides of [
    { candidateRevision: 9 },
    { basePublishedRevision: 8 },
    { publishedRevision: 10 },
    { draftRevision: 3 },
  ]) {
    s.succeed({ app: { ...saved, ...overrides } });
    await assert.rejects(
      s.backend.saveDraft(command),
      (error: unknown) => error instanceof BackendError && error.uncertain,
    );
  }
});

test("publication receipts match the reviewed private counter and exact global candidate", async () => {
  const s = setup();
  const command = {
    appId: "app",
    expectedRevision: 2,
    expectedPublishedRevision: 9,
    candidateRevision: 12,
    operationId: "publish-reviewed",
  };
  const published = {
    ...appDocument,
    draftRevision: 2,
    candidateRevision: 12,
    publishedRevision: 12,
    basePublishedRevision: 12,
  };
  s.failExecution(new TypeError("Commit response lost"));
  await assert.rejects(
    s.backend.publishApp(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  s.succeed({ app: published });
  assert.equal((await s.backend.publishApp(command)).publishedRevision, 12);
  assert.equal(s.requests[0], s.requests[1]);
  for (const overrides of [
    { candidateRevision: 13, publishedRevision: 13, basePublishedRevision: 13 },
    { publishedRevision: 2, basePublishedRevision: 2 },
    { draftRevision: 3 },
    { basePublishedRevision: 9 },
    { publishedDefinition: { ...definition, title: "Wrong content" } },
  ]) {
    s.succeed({ app: { ...published, ...overrides } });
    await assert.rejects(
      s.backend.publishApp(command),
      (error: unknown) => error instanceof BackendError && error.uncertain,
    );
  }
});

test("historical acknowledgments remain exact legacy data and never invent capabilities", async () => {
  const s = setup();
  const legacy = {
    id: "app",
    workspaceId: "workspace",
    name: "Notebook",
    draftRevision: 1,
    publishedRevision: 0,
    definition,
    publishedDefinition: null,
  };
  const command = {
    appId: "app",
    expectedRevision: 0,
    expectedPublishedRevision: 0,
    operationId: "legacy-receipt",
    definition,
  };
  s.succeed({ app: legacy });
  const result = await s.backend.saveDraft(command);
  assert.equal(result.role, undefined);
  assert.equal(result.capabilities, undefined);
  assert.equal(result.candidateRevision, undefined);
  s.succeed({ app: { ...legacy, candidateRevision: 1 } });
  await assert.rejects(
    s.backend.saveDraft(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  s.succeed({
    app: { ...legacy, publishedRevision: 1, publishedDefinition: definition },
  });
  const published = await s.backend.publishApp({
    appId: "app",
    expectedRevision: 1,
    expectedPublishedRevision: 0,
    candidateRevision: 1,
    operationId: "legacy-publish",
  });
  assert.equal(published.capabilities, undefined);
});

test("archive receipts require this app and its owner role with only access revocation enabled", async () => {
  const s = setup();
  const command = { appId: "app", operationId: "archive" };
  const archived = {
    ...appDocument,
    archived: true,
    capabilities: {
      editDefinition: false,
      share: false,
      writeRecords: false,
      archive: false,
      revokeAccess: true,
    },
  };
  s.succeed({ app: archived });
  assert.equal((await s.backend.archiveApp(command)).archived, true);
  for (const value of [
    appDocument,
    { ...archived, id: "another" },
    { ...archived, role: "builder" },
    { ...archived, capabilities: appDocument.capabilities },
  ]) {
    s.succeed({ app: value });
    await assert.rejects(
      s.backend.archiveApp(command),
      (error: unknown) => error instanceof BackendError && error.uncertain,
    );
  }
});

test("engine-neutral access reads accept shared metadata and reject private payloads or policy-specific capability substitution", async () => {
  const s = setup();
  for (const engine of ["bounded.v1", "appspec.v1"] as const) {
    for (const role of ["owner", "builder", "member", "viewer"] as const) {
      for (const archived of [false, true]) {
        const builder = role === "owner" || role === "builder";
        const value = {
          id: "app",
          workspaceId: "workspace",
          name: "Shared metadata",
          engine,
          role,
          archived,
          capabilities: {
            editDefinition: builder && !archived,
            share: builder && !archived,
            writeRecords: builder && !archived,
            archive: role === "owner" && !archived,
            revokeAccess: builder,
          },
        };
        s.succeed({ app: value });
        assert.deepEqual(await s.backend.getAppAccess("app"), value);
      }
    }
  }
  const value = {
    id: "app",
    workspaceId: "workspace",
    name: "Shared metadata",
    engine: "appspec.v1",
    role: "member",
    archived: false,
    capabilities: {
      editDefinition: false,
      share: false,
      writeRecords: false,
      archive: false,
      revokeAccess: false,
    },
  };
  for (const invalid of [
    { ...value, draft: { private: "data" } },
    { ...value, engine: undefined },
    { ...value, id: "other" },
    { ...value, capabilities: { ...value.capabilities, writeRecords: true } },
    { ...value, role: undefined },
  ]) {
    s.succeed({ app: invalid });
    await assert.rejects(
      s.backend.getAppAccess("app"),
      (error: unknown) => error instanceof BackendError && !error.uncertain,
    );
  }
  assert.equal(JSON.parse(s.requests[0]).op, "getAppAccess");
});

test("generic archive extracts acknowledgement metadata from full AppSpec and historical bounded receipts", async () => {
  const s = setup(),
    command = { appId: "app", operationId: "generic-archive" };
  const shared = {
    id: "app",
    workspaceId: "workspace",
    name: "Archive",
    role: "owner",
    archived: true,
    capabilities: {
      editDefinition: false,
      share: false,
      writeRecords: false,
      archive: false,
      revokeAccess: true,
    },
  };
  for (const body of [
    {
      ...shared,
      draftRevision: 4,
      publishedRevision: 2,
      candidateRevision: 7,
      basePublishedRevision: 2,
      definition: { private: true },
      publishedDefinition: { private: true },
    },
    {
      ...shared,
      engine: "appspec.v1",
      allowedActions: [],
      controlRevision: 44,
      version: { spec: { private: "x".repeat(300_000) } },
      draft: { spec: { private: true } },
      generation: null,
    },
  ]) {
    s.succeed({ app: body });
    const result = await s.backend.archiveAppAccess(command);
    assert.deepEqual(result, {
      ...shared,
      ...("engine" in body ? { engine: body.engine } : {}),
    });
    assert.equal("definition" in result, false);
    assert.equal("draft" in result, false);
    assert.equal("version" in result, false);
  }
  for (const body of [
    { ...shared, id: "other" },
    { ...shared, role: "builder" },
    { ...shared, archived: false },
    { ...shared, capabilities: { ...shared.capabilities, share: true } },
  ]) {
    s.succeed({ app: body });
    await assert.rejects(
      s.backend.archiveAppAccess(command),
      (error: unknown) => error instanceof BackendError && error.uncertain,
    );
  }
  assert.deepEqual(JSON.parse(s.requests[0]), { op: "archiveApp", ...command });
});
