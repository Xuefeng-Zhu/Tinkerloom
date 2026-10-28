import assert from "node:assert/strict";
import { test } from "node:test";
import { AppwriteBackend, type ExecutionResult, type SdkAdapter } from "./core";
import { BackendError } from "./errors";
import { validatePublicConfig } from "./config";

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
      { id: "a", name: "A" },
      { id: "a", name: "B" },
    ],
  });
  await assert.rejects(
    scenario.backend.listWorkspaces(),
    (error: unknown) =>
      error instanceof BackendError && error.kind === "invalid_response",
  );
  scenario.succeed({
    apps: [{ id: "a", name: "Private app", workspaceId: "another-workspace" }],
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
