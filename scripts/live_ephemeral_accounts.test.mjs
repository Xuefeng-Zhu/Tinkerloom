/** Offline only. Auth endpoints below are explicit stubs; no Cloud proof. */
import test from "node:test";
import assert from "node:assert/strict";
import { runInNewContext } from "node:vm";
import {
  EphemeralSyntheticAccounts,
  readSyntheticCredentials,
} from "./live_ephemeral_accounts.mjs";
import { runFullSmoke } from "./live_full_smoke.mjs";
import { runMediaSmoke } from "./live_media_smoke.mjs";
const labels = ["owner", "builder", "member", "viewer", "outsider"];
const configuration = () => ({
  endpoint: "https://appwrite.invalid/v1",
  projectId: "synthetic-project",
  functionId: "synthetic-core",
  databaseId: "tinkerloom",
  bucketId: "synthetic-media",
  workerFunctionId: "synthetic-worker",
  origin: "http://localhost:8426",
  sourceCommit: "fc71abc",
  sourceSha256: "a".repeat(64),
  workerSourceCommit: "fc71abc",
  workerSourceSha256: "a".repeat(64),
  coreDeploymentId: "synthetic-core-deploy",
  workerDeploymentId: "synthetic-worker-deploy",
  maxHttp: 300,
  timeoutMs: 2000,
  readyPolls: 1,
  pollMs: 1000,
  observeRelease: false,
  releasePolls: 1,
  twentyDistinct: false,
});
const credentials = (label) => ({
  id: `qa-${label}`,
  email: `tinkerloom-offline-${label}@example.test`,
  password: `T!synthetic-${label}-private-marker-012a9`,
});
const reply = (status, data, headers = {}) =>
  new Response(data === undefined ? null : JSON.stringify(data), {
    status,
    headers,
  });
async function rejectsCode(
  action,
  expected = "configuration_invalid",
  privateMarker = "",
) {
  let caught;
  try {
    await action();
  } catch (error) {
    caught = error;
  }
  assert.equal(caught?.code === expected, true, "expected fixed error code");
  assert.equal(
    !privateMarker || !String(caught).includes(privateMarker),
    true,
    "error must not echo private input",
  );
}
function noPrivate(value, secrets) {
  const text = JSON.stringify(value);
  for (const secret of secrets)
    assert.equal(
      text.includes(secret),
      false,
      "private value must not appear in output",
    );
  for (const field of [
    "password",
    "email",
    "Cookie",
    "dataBase64",
    "requestBody",
  ])
    assert.equal(
      text.includes(`"${field}"`),
      false,
      "private field must not appear in output",
    );
}

test("strict credentials accept plain/null-prototype data and return a frozen independent copy", async () => {
  for (const input of [
    credentials("owner"),
    Object.assign(Object.create(null), credentials("owner")),
  ]) {
    const privateValues = new Set();
    let context;
    const result = await readSyntheticCredentials(
      (label, metadata) => {
        assert.equal(label, "owner");
        context = metadata;
        return input;
      },
      "owner",
      "qa-offline",
      privateValues,
    );
    assert.equal(Object.isFrozen(context), true);
    assert.equal(context.runId, "qa-offline");
    assert.equal(Object.isFrozen(result), true);
    assert.notEqual(result, input);
    assert.equal(
      result.id === input.id &&
        result.email === input.email &&
        result.password === input.password,
      true,
    );
    assert.equal(
      privateValues.has(input.email) && privateValues.has(input.password),
      true,
    );
  }
  const result = await readSyntheticCredentials(
    async () => credentials("owner"),
    "owner",
    "qa-offline",
    new Set(),
  );
  assert.equal(result.id, "qa-owner");
});
test("strict credentials reject missing extras symbols nonplain and non-synthetic identities", async () => {
  const valid = credentials("owner"),
    missing = { ...valid };
  delete missing.password;
  const variants = [
    null,
    [],
    new Date(),
    new Map(),
    new (class Credential {})(),
    missing,
    { ...valid, extra: "private" },
    { ...valid, [Symbol("private")]: "private" },
    { ...valid, id: "bad/id" },
    { ...valid, email: "person@example.com" },
    { ...valid, email: "person@example.test" },
    { ...valid, password: "short" },
    { ...valid, password: "x".repeat(129) },
    { ...valid, password: "private\nvalue" },
  ];
  for (const value of variants)
    await rejectsCode(() =>
      readSyntheticCredentials(() => value, "owner", "qa-offline", new Set()),
    );
  await rejectsCode(() =>
    readSyntheticCredentials(null, "owner", "qa-offline", new Set()),
  );
  await rejectsCode(() =>
    readSyntheticCredentials(
      () => valid,
      "capacity_01",
      "qa-offline",
      new Set(),
    ),
  );
});
test("credential getters and hidden serialization accessors are never executed", async () => {
  for (const key of ["id", "email", "password"]) {
    const value = credentials("owner");
    let invoked = 0;
    Object.defineProperty(value, key, {
      get() {
        invoked++;
        return "private getter";
      },
      enumerable: true,
    });
    await rejectsCode(() =>
      readSyntheticCredentials(() => value, "owner", "qa-offline", new Set()),
    );
    assert.equal(invoked, 0, "credential getter must not execute");
  }
  const value = credentials("owner");
  let serialized = 0;
  Object.defineProperty(value, "toJSON", {
    get() {
      serialized++;
      return () => "private";
    },
    enumerable: false,
  });
  await rejectsCode(() =>
    readSyntheticCredentials(() => value, "owner", "qa-offline", new Set()),
  );
  assert.equal(serialized, 0, "hidden serialization getter must not execute");
});
test("synchronous thenable accessor is rejected before await can execute its getter", async () => {
  const value = credentials("owner");
  let invoked = 0;
  Object.defineProperty(value, "then", {
    get() {
      invoked++;
      return undefined;
    },
    enumerable: false,
  });
  await rejectsCode(() =>
    readSyntheticCredentials(() => value, "owner", "qa-offline", new Set()),
  );
  assert.equal(invoked, 0, "then getter must not execute during validation");
});
test("native asynchronous and cross-realm Promise providers preserve strict credential validation", async () => {
  const known = credentials("owner");
  for (const provider of [
    async () => known,
    () => runInNewContext("Promise.resolve(value)", { value: known }),
  ]) {
    const result = await readSyntheticCredentials(
      provider,
      "owner",
      "qa-offline",
      new Set(),
    );
    assert.equal(result.id, "qa-owner");
    assert.equal(
      result.email === known.email && result.password === known.password,
      true,
    );
  }
});
test("native Promise own then/constructor accessors are rejected without invocation", async () => {
  for (const key of ["then", "constructor"]) {
    const value = Promise.resolve(credentials("owner"));
    let invoked = 0;
    Object.defineProperty(value, key, {
      get() {
        invoked++;
        return key === "then" ? Promise.prototype.then : Promise;
      },
    });
    await rejectsCode(() =>
      readSyntheticCredentials(() => value, "owner", "qa-offline", new Set()),
    );
    assert.equal(invoked, 0, "Promise accessor must not execute");
  }
});
test("provider exceptions use a fixed sanitized error without exposing input", async () => {
  const marker = "private-provider-exception-marker";
  await rejectsCode(
    () =>
      readSyntheticCredentials(
        () => {
          throw new Error(marker);
        },
        "owner",
        "qa-offline",
        new Set(),
      ),
    "configuration_invalid",
    marker,
  );
});

test("pool uses exactly one ordinary account POST per allowed label and at most five identities", async () => {
  const calls = [];
  const pool = new EphemeralSyntheticAccounts(configuration(), {
    fetchImpl: async (url, options) => {
      const body = JSON.parse(options.body);
      calls.push({
        path: new URL(url).pathname,
        method: options.method,
        body,
        headers: options.headers,
      });
      return reply(201, { $id: body.userId });
    },
  });
  const resolved = [];
  for (const label of labels) {
    const first = await pool.actorCredentials(label),
      again = await pool.actorCredentials(label);
    assert.equal(first, again);
    assert.equal(Object.isFrozen(first), true);
    resolved.push(first);
  }
  assert.equal(calls.length, 5);
  assert.equal(new Set(calls.map((c) => c.body.userId)).size, 5);
  assert.equal(
    calls.every((c) => c.path === "/v1/account" && c.method === "POST"),
    true,
  );
  assert.equal(
    calls.every((c) =>
      Object.keys(c.headers).every((h) => !/key|authorization|jwt/i.test(h)),
    ),
    true,
  );
  await rejectsCode(() => pool.actorCredentials("sixth"));
  assert.equal(calls.length, 5);
  const snapshot = pool.snapshot();
  assert.equal(snapshot.accountCreateHttpRequests, 5);
  assert.equal(snapshot.maxSyntheticAccounts, 5);
  assert.equal(
    snapshot.accounts.every(
      (a) => a.creationStatus === "created" && a.httpStatus === 201,
    ),
    true,
  );
  noPrivate(
    snapshot,
    resolved.flatMap((c) => [c.email, c.password]),
  );
  assert.equal(snapshot.credentialsPersisted, false);
  assert.equal(snapshot.authenticationBypassed, false);
  assert.equal(snapshot.automaticCreationRetries, 0);
  snapshot.accounts[0].creationStatus = "tampered";
  assert.equal(pool.snapshot().accounts[0].creationStatus, "created");
  pool.forget();
});
test("simultaneous acquire coalesces one in-flight create and returns the same credentials", async () => {
  let finish,
    count = 0,
    id;
  const pool = new EphemeralSyntheticAccounts(configuration(), {
    fetchImpl: async (_, options) => {
      count++;
      id = JSON.parse(options.body).userId;
      return new Promise((resolve) => {
        finish = resolve;
      });
    },
  });
  const attempts = Array.from({ length: 20 }, () =>
    pool.actorCredentials("owner"),
  );
  assert.equal(count, 1);
  finish(reply(201, { $id: id }));
  const result = await Promise.all(attempts);
  assert.equal(
    result.every((v) => v === result[0]),
    true,
  );
  assert.equal(count, 1);
  assert.equal(pool.snapshot().accountCreateHttpRequests, 1);
  pool.forget();
});
test("unknown transport rate-limit and mismatched create never retry or replace that identity", async () => {
  for (const mode of ["unknown", "rate", "mismatch"]) {
    let requests = 0;
    const ids = [];
    const pool = new EphemeralSyntheticAccounts(configuration(), {
      fetchImpl: async (_, options) => {
        requests++;
        ids.push(JSON.parse(options.body).userId);
        if (mode === "unknown") throw new Error("private transport marker");
        return mode === "rate"
          ? reply(
              429,
              {
                type: "general_rate_limit_exceeded",
                message: "private server marker",
              },
              { "Retry-After": "1" },
            )
          : reply(201, { $id: "different-account" });
      },
    });
    const expected =
      mode === "unknown"
        ? "request_transport_failure"
        : "configuration_invalid";
    for (let i = 0; i < 4; i++)
      await rejectsCode(
        () => pool.actorCredentials("owner"),
        expected,
        "private",
      );
    assert.equal(requests, 1);
    assert.equal(new Set(ids).size, 1);
    const snapshot = pool.snapshot();
    assert.equal(snapshot.accountCreateHttpRequests, 1);
    assert.equal(snapshot.accounts[0].creationStatus, "unconfirmed");
    noPrivate(snapshot, ["private transport marker", "private server marker"]);
    pool.forget();
  }
});
test("forget closes the pool, clears exposed state and rejects an in-flight credential result", async () => {
  let finish,
    id,
    calls = 0;
  const pool = new EphemeralSyntheticAccounts(configuration(), {
    fetchImpl: async (_, options) => {
      calls++;
      id = JSON.parse(options.body).userId;
      return new Promise((resolve) => {
        finish = resolve;
      });
    },
  });
  const pending = pool.actorCredentials("owner");
  const observed = pending.then(
    () => "unexpected_success",
    (e) => e.code,
  );
  pool.forget();
  assert.deepEqual(pool.snapshot().accounts, []);
  finish(reply(201, { $id: id }));
  assert.equal(await observed, "configuration_invalid");
  await rejectsCode(() => pool.actorCredentials("owner"));
  await rejectsCode(() => pool.actorCredentials("builder"));
  assert.equal(calls, 1);
  assert.deepEqual(pool.snapshot().accounts, []);
});

function fakeProbeAuth({ mismatchLabel } = {}) {
  const known = new Map(
      labels.map((label) => [credentials(label).email, credentials(label)]),
    ),
    sessions = new Map(),
    requests = [],
    secretValues = [];
  let sequence = 0;
  const fetchImpl = async (url, options) => {
    const path = new URL(url).pathname.slice(3),
      body = options.body ? JSON.parse(options.body) : null,
      token = options.headers.Cookie?.split("=", 2)[1];
    requests.push({ method: options.method, path, token });
    if (path === "/account" && options.method === "POST")
      throw new Error("unexpected_account_creation");
    if (path === "/account/sessions/email" && options.method === "POST") {
      const account = known.get(body.email);
      assert.equal(!!account && account.password === body.password, true);
      const cookie = `offline-session-private-${++sequence}`;
      sessions.set(cookie, account);
      secretValues.push(cookie);
      return reply(
        201,
        {},
        { "Set-Cookie": `a_session=${cookie}; Path=/; HttpOnly` },
      );
    }
    if (path === "/account" && options.method === "GET") {
      const account = sessions.get(token);
      assert.equal(!!account, true);
      return reply(200, {
        $id:
          account.id === `qa-${mismatchLabel}` ? "wrong-account" : account.id,
      });
    }
    if (path === "/account/sessions/current" && options.method === "DELETE") {
      assert.equal(
        sessions.has(token),
        true,
        "only a session this probe created may be removed",
      );
      sessions.delete(token);
      return reply(204, undefined, {
        "Set-Cookie": "a_session=; Max-Age=0; Path=/",
      });
    }
    if (path.startsWith("/functions/") && options.method === "POST")
      return reply(503, { type: "backend_unavailable" });
    throw new Error("unexpected_offline_endpoint");
  };
  return { fetchImpl, requests, secretValues, sessions };
}
for (const [name, run, count] of [
  ["full", runFullSmoke, 5],
  ["media", runMediaSmoke, 2],
]) {
  test(`${name} hook reuses credentials but still performs normal sign-in/account check and own-session signout`, async () => {
    const auth = fakeProbeAuth(),
      requested = [];
    const report = await run(configuration(), {
      fetchImpl: auth.fetchImpl,
      actorCredentials: (label) => {
        requested.push(label);
        return credentials(label);
      },
      sleep: async () => {
        throw new Error("no auth/business retries permitted");
      },
    });
    const calls = (method, path) =>
      auth.requests.filter((r) => r.method === method && r.path === path);
    assert.equal(requested.length, count);
    assert.equal(new Set(requested).size, count);
    assert.equal(calls("POST", "/account").length, 0);
    assert.equal(calls("POST", "/account/sessions/email").length, count);
    assert.equal(calls("GET", "/account").length, count);
    assert.equal(calls("DELETE", "/account/sessions/current").length, count);
    assert.equal(auth.sessions.size, 0);
    assert.equal(report.accounts.length, count);
    assert.equal(
      report.accounts.every((a) => a.creationStatus === "reused_verified"),
      true,
    );
    assert.equal(report.budget.syntheticAccountsCreated, 0);
    assert.equal(report.budget.reusedVerifiedSyntheticAccounts, count);
    assert.equal(
      report.status,
      "failed",
      "503 business stubs must not produce a successful live report",
    );
    assert.equal(report.summary.failed > 0 && report.summary.blocked > 0, true);
    noPrivate(report, [
      ...auth.secretValues,
      ...requested.flatMap((label) => [
        credentials(label).email,
        credentials(label).password,
      ]),
    ]);
  });
  test(`${name} hook fails mismatched authenticated identity and does not count it as verified reuse`, async () => {
    const auth = fakeProbeAuth({ mismatchLabel: "owner" });
    const report = await run(configuration(), {
      fetchImpl: auth.fetchImpl,
      actorCredentials: (label) => credentials(label),
      sleep: async () => {
        throw new Error("unexpected retry");
      },
    });
    const owner = report.accounts.find((a) => a.id === "qa-owner");
    assert.equal(owner?.creationStatus, "unconfirmed");
    assert.equal(
      report.checks.find((c) => c.name === "authenticate_owner")?.status,
      "failed",
    );
    assert.equal(report.budget.reusedVerifiedSyntheticAccounts, count - 1);
    assert.equal(report.budget.syntheticAccountsCreated, 0);
    assert.equal(
      auth.requests.filter((r) => r.path === "/account" && r.method === "POST")
        .length,
      0,
    );
    assert.equal(auth.sessions.size, 0);
    noPrivate(report, [
      ...auth.secretValues,
      ...labels.flatMap((label) => [
        credentials(label).email,
        credentials(label).password,
      ]),
    ]);
  });
}
