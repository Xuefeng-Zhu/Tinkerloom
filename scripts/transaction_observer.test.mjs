import test from "node:test";
import assert from "node:assert/strict";
import {
  diagnosticCategories,
  makeTransactionObserver,
  observerLimits,
} from "./transaction_observer.mjs";

const url = "https://example.invalid/v1/functions/tinkerloom-core/executions";
const request = (op = "spec.execute") => ({
  method: "POST",
  body: JSON.stringify({ body: JSON.stringify({ op }) }),
});
const execution = (extra = {}) => ({
  $id: "PRIVATE_EXECUTION",
  deploymentId: "PRIVATE_DEPLOYMENT",
  status: "completed",
  responseStatusCode: 409,
  responseBody: JSON.stringify({ error: "transaction_conflict" }),
  errors:
    "transaction_diagnostic:abortConfirmed\ntransaction_diagnostic:retryStarted\n",
  logs: "",
  ...extra,
});
const reply = (extra) =>
  new Response(JSON.stringify(execution(extra)), { status: 201 });
const observed = async (response = reply(), input = url, init = request()) => {
  let calls = 0;
  const observer = makeTransactionObserver(() => {
    calls++;
    return Promise.resolve(response);
  });
  assert.equal(await observer.fetch(input, init), response);
  await observer.settled();
  return { observer, response, snapshot: observer.snapshot(), calls };
};

test("transparent exact arguments, original Response identity, body and headers", async () => {
  const init = request(),
    response = reply();
  const headers = new Proxy(
    {},
    {
      get() {
        throw new Error("must not inspect headers");
      },
    },
  );
  init.headers = headers;
  const receiver = { marker: true };
  let calls = 0;
  const observer = makeTransactionObserver(function (...args) {
    calls++;
    assert.equal(this, receiver);
    assert.equal(args.length, 3);
    assert.equal(args[0], url);
    assert.equal(args[1], init);
    assert.equal(args[2], "extra");
    return Promise.resolve(response);
  });
  assert.equal(
    await observer.fetch.call(receiver, url, init, "extra"),
    response,
  );
  assert.equal(response.bodyUsed, false);
  assert.deepEqual(JSON.parse(await response.text()), execution());
  await observer.settled();
  assert.equal(calls, 1);
  assert.equal(observer.snapshot().diagnostics.abortConfirmed, 1);
});

test("only exact core execution POST targets are cloned", async () => {
  for (const [input, init] of [
    [url, { method: "GET" }],
    [url, {}],
    [url.replace("tinkerloom-core", "tinkerloom-worker"), request()],
    [url + "/private", request()],
    [url.replace("/v1/", "/v2/"), request()],
    ["not a url", request()],
    [
      {
        toString() {
          throw new Error("secret");
        },
      },
      request(),
    ],
  ]) {
    const response = new Response("original");
    response.clone = () => {
      throw new Error("must not clone");
    };
    const { snapshot, calls } = await observed(response, input, init);
    assert.equal(calls, 1);
    assert.equal(snapshot.counts.matchedRequests, 0);
    assert.equal(await response.text(), "original");
  }
});

test("current Appwrite wire envelope and requested data.op shape are allowlisted", async () => {
  for (const body of [
    JSON.stringify({ data: { op: "acceptInvitation" } }),
    JSON.stringify({
      body: JSON.stringify({ op: "acceptInvitation", token: "SECRET" }),
    }),
  ]) {
    const { snapshot } = await observed(reply(), url, { method: "post", body });
    assert.equal(snapshot.operations.acceptInvitation, 1);
    assert.equal(snapshot.conflictEvents[0].operation, "acceptInvitation");
  }
});

test("ArrayBuffer and sliced views request bodies use exact byte extent", async () => {
  const encoded = new TextEncoder().encode(request("spec.publish").body);
  const padded = new Uint8Array(encoded.length + 8);
  padded.set(encoded, 4);
  for (const body of [
    encoded.buffer,
    padded.subarray(4, 4 + encoded.length),
    new DataView(padded.buffer, 4, encoded.length),
  ]) {
    const { snapshot } = await observed(reply(), url, { method: "POST", body });
    assert.equal(snapshot.operations["spec.publish"], 1);
  }
});

test("Request clone inspection does not consume the outgoing Request", async () => {
  const input = new Request(url, request("setGrant"));
  const observer = makeTransactionObserver(async (actual) => {
    assert.equal(actual, input);
    assert.equal(actual.bodyUsed, false);
    assert.equal(await actual.text(), request("setGrant").body);
    return reply();
  });
  await observer.fetch(input);
  await observer.settled();
  assert.equal(observer.snapshot().operations.setGrant, 1);
});

test("init stream is never read or replaced to inspect an operation", async () => {
  let pulls = 0;
  const body = new ReadableStream(
    {
      pull() {
        pulls++;
      },
    },
    { highWaterMark: 0 },
  );
  const init = { method: "POST", body, duplex: "half" };
  const observer = makeTransactionObserver((actual, actualInit) => {
    assert.equal(actual, url);
    assert.equal(actualInit, init);
    assert.equal(actualInit.body, body);
    return reply();
  });
  await observer.fetch(url, init);
  await observer.settled();
  assert.equal(pulls, 0);
  assert.equal(observer.snapshot().operations.unavailable, 1);
  await body.cancel();
});

test("unknown request ops and raw errors, IDs, headers, bodies never enter snapshots", async () => {
  const secret = "SECRET_PASSWORD_COOKIE_TOKEN_APPID_EMAIL@example.test";
  const response = reply({
    $id: secret,
    deploymentId: secret,
    requestHeaders: { Cookie: secret },
    responseHeaders: { Authorization: secret },
    requestPath: secret,
    trigger: secret,
    responseBody: JSON.stringify({ error: secret, data: { id: secret } }),
    errors: `${secret}\ntransaction_diagnostic:${secret}\n[${secret}] transaction_diagnostic:retryStarted`,
    logs: secret,
  });
  const { snapshot } = await observed(response, url + "?secret=" + secret, {
    method: "POST",
    body: JSON.stringify({ data: { op: secret, password: secret } }),
    headers: { Cookie: secret },
  });
  assert.equal(snapshot.operations.unavailable, 1);
  assert.equal(snapshot.errorCodes.unrecognized_error, 1);
  assert.equal(snapshot.deployments.invalid, 1);
  assert.equal(JSON.stringify(snapshot).includes(secret), false);
  assert.equal(snapshot.conflictEvents[0].errorCode, "unrecognized_error");
  assert.equal(
    Object.values(snapshot.diagnostics).reduce((a, b) => a + b, 0),
    0,
  );
});

test("exact thirteen diagnostics, combined errors+logs cap twelve, unknown lines use no budget", async () => {
  const all = diagnosticCategories.map(
    (name) => `transaction_diagnostic:${name}`,
  );
  const { snapshot } = await observed(
    reply({
      errors: `transaction_diagnostic:UnknownSecret\n${all.slice(0, 6).join("\r\n")}`,
      logs: `${all.slice(6).join("\n")}\ntransaction_diagnostic:retryStarted`,
    }),
  );
  assert.equal(Object.keys(snapshot.diagnostics).length, 13);
  assert.equal(
    Object.values(snapshot.diagnostics).reduce((a, b) => a + b, 0),
    12,
  );
  assert.equal(snapshot.diagnostics.cleanupUnconfirmed, 0);
  assert.equal(snapshot.diagnostics.retryStarted, 1);
});

test("only whole marker lines match, never messages with trailing content or prefix", async () => {
  const { snapshot } = await observed(
    reply({
      errors: [
        "prefix transaction_diagnostic:retryStarted",
        "transaction_diagnostic:retryStarted trailing-secret",
        "transaction_diagnostic:retryStarted_extra",
        "transaction_diagnostic:retryStarted:secret",
        "  transaction_diagnostic:retryStarted  ",
      ].join("\n"),
      logs: "transaction_diagnostic:abortConfirmed",
    }),
  );
  assert.equal(snapshot.diagnostics.retryStarted, 1);
  assert.equal(snapshot.diagnostics.abortConfirmed, 1);
});

test("unknown statuses and malformed deployment become fixed categories", async () => {
  const { snapshot } = await observed(
    reply({
      status: "secret-status",
      responseStatusCode: "409",
      deploymentId: { secret: "secret" },
      responseBody: "[]",
      errors: "",
    }),
  );
  assert.equal(snapshot.executionStatuses.unavailable, 1);
  assert.equal(snapshot.functionStatuses.other, 1);
  assert.equal(snapshot.deployments.invalid, 1);
  assert.equal(snapshot.errorCodes.unavailable, 1);
  assert.equal(snapshot.conflictEvents.length, 0);
});

test("outer allowlisted error and HTTP409 retained without raw response metadata", async () => {
  const { snapshot } = await observed(
    new Response(
      JSON.stringify({ type: "general_unauthorized_scope", message: "SECRET" }),
      { status: 409 },
    ),
  );
  assert.equal(snapshot.errorCodes.general_unauthorized_scope, 1);
  assert.equal(snapshot.conflictEvents[0].httpStatus, "409");
  assert.equal(JSON.stringify(snapshot).includes("SECRET"), false);
});

test("fetch rejection identity and single-call behavior are preserved", async () => {
  const error = new Error("SECRET_FAILURE"),
    observer = makeTransactionObserver(() => {
      throw error;
    });
  await assert.rejects(
    observer.fetch(url, request()),
    (actual) => actual === error,
  );
  await observer.settled();
  assert.equal(observer.snapshot().counts.fetchFailures, 1);
  assert.equal(
    JSON.stringify(observer.snapshot()).includes("SECRET_FAILURE"),
    false,
  );
});

test("clone failure cannot change fetch success or consume original body", async () => {
  const response = new Response("caller original");
  response.clone = () => {
    throw new Error("SECRET_CLONE");
  };
  const { snapshot } = await observed(response);
  assert.equal(snapshot.counts.unreadableResponses, 1);
  assert.equal(await response.text(), "caller original");
  assert.equal(JSON.stringify(snapshot).includes("SECRET_CLONE"), false);
});

test("invalid JSON, nonobject JSON and invalid UTF8 are bounded inspection failures", async () => {
  for (const value of [
    "not json SECRET",
    "[]",
    "null",
    new Uint8Array([0xff]),
  ]) {
    const { snapshot, response } = await observed(new Response(value));
    assert.equal(snapshot.counts.unreadableResponses, 1);
    assert.equal(snapshot.conflictEvents.length, 0);
    assert.equal(response.bodyUsed, false);
    await response.arrayBuffer();
  }
});

test("ArrayBuffer response over byte limit is ignored while original remains complete", async () => {
  const bytes = new Uint8Array(observerLimits.responseBytes + 1).fill(65);
  const { snapshot, response } = await observed(new Response(bytes.buffer));
  assert.equal(snapshot.counts.unreadableResponses, 1);
  assert.equal(snapshot.counts.inspectedResponses, 0);
  assert.equal((await response.arrayBuffer()).byteLength, bytes.length);
});

test("multi-chunk response overflow does not cancel original stream", async () => {
  const chunk = new Uint8Array(512 * 1024).fill(66);
  let sourceCancelled = false;
  const stream = new ReadableStream({
    start(controller) {
      for (let i = 0; i < 3; i++) controller.enqueue(chunk);
      controller.close();
    },
    cancel() {
      sourceCancelled = true;
    },
  });
  const { snapshot, response } = await observed(new Response(stream));
  assert.equal(snapshot.counts.unreadableResponses, 1);
  assert.equal(sourceCancelled, false);
  assert.equal((await response.arrayBuffer()).byteLength, chunk.length * 3);
});

test("stream read failures are private and never replace original Response", async () => {
  const response = new Response(
    new ReadableStream({
      start(controller) {
        controller.error(new Error("SECRET_STREAM"));
      },
    }),
  );
  const { snapshot } = await observed(response);
  assert.equal(snapshot.counts.unreadableResponses, 1);
  assert.equal(JSON.stringify(snapshot).includes("SECRET_STREAM"), false);
  await assert.rejects(response.text(), /SECRET_STREAM/);
});

test("hung clone read is deadline-bounded and does not delay fetch result", async () => {
  let sourceCancelled = false;
  const response = new Response(
    new ReadableStream({
      cancel() {
        sourceCancelled = true;
      },
    }),
  );
  const observer = makeTransactionObserver(() => response);
  const sentinel = Symbol("late");
  let timer;
  assert.equal(
    await Promise.race([
      observer.fetch(url, request()),
      new Promise((resolve) => {
        timer = setTimeout(() => resolve(sentinel), 100);
      }),
    ]),
    response,
  );
  clearTimeout(timer);
  const started = Date.now();
  await observer.settled();
  assert.ok(
    Date.now() - started <= observerLimits.inspectionMilliseconds + 1000,
  );
  assert.equal(observer.snapshot().counts.unreadableResponses, 1);
  assert.equal(sourceCancelled, false);
  await response.body.cancel();
});

test("request/inner response/log byte bounds cannot create unbounded reports", async () => {
  const large = "SECRET".repeat(observerLimits.requestBytes);
  const { snapshot } = await observed(
    reply({ responseBody: large, errors: large, logs: large }),
    url,
    { method: "POST", body: large },
  );
  assert.equal(snapshot.counts.unreadableResponses, 1); // Entire envelope also exceeds 1MiB.
  assert.equal(snapshot.operations.unavailable, 1);
  assert.ok(JSON.stringify(snapshot).length < 20000);
  const inner = await observed(
    reply({
      responseBody: " ".repeat(observerLimits.functionBodyBytes + 1),
      errors: " ".repeat(observerLimits.logBytes + 1),
      logs: "transaction_diagnostic:abortConfirmed",
    }),
  );
  assert.equal(inner.snapshot.errorCodes.unavailable, 1);
  assert.equal(inner.snapshot.diagnostics.abortConfirmed, 1);
});

test("maximum eighty conflict events and detached snapshot copies", async () => {
  const observer = makeTransactionObserver(() => reply());
  for (let i = 0; i < 83; i++) {
    await observer.fetch(url, request());
    await observer.settled();
  }
  const snapshot = observer.snapshot();
  assert.equal(snapshot.conflictEvents.length, 80);
  assert.equal(snapshot.counts.conflictEventsDropped, 3);
  assert.equal(snapshot.diagnostics.retryStarted, 83);
  snapshot.counts.matchedRequests = -5;
  snapshot.conflictEvents[0].diagnostics.retryStarted = -1;
  snapshot.conflictEvents.push({ secret: "not observer state" });
  assert.equal(observer.snapshot().counts.matchedRequests, 83);
  assert.equal(observer.snapshot().conflictEvents.length, 80);
  assert.equal(
    observer.snapshot().conflictEvents[0].diagnostics.retryStarted,
    1,
  );
});

test("at most eight simultaneous pending inspections; no retries or extra fetch", async () => {
  const releases = [];
  let calls = 0;
  const observer = makeTransactionObserver(() => {
    calls++;
    return new Promise((resolve) => releases.push(() => resolve(reply())));
  });
  const results = Array.from({ length: 20 }, () =>
    observer.fetch(url, request()),
  );
  for (const release of releases) release();
  const responses = await Promise.all(results);
  await observer.settled();
  assert.equal(calls, 20);
  assert.equal(observer.snapshot().counts.inspectedResponses, 8);
  assert.equal(observer.snapshot().counts.inspectionsSkipped, 12);
  assert.equal(
    responses.every((r) => r instanceof Response),
    true,
  );
  await Promise.all(responses.map((r) => r.text()));
});
