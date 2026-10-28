import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import { accountTransport, type AccountSession } from "./FullRegistry";
function deferred() {
  let resolve!: (value: unknown) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<unknown>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
function fixture() {
  let session: AccountSession = { accountId: "alice", epoch: 1, active: true };
  let alive = true,
    calls = 0,
    expired = 0;
  const next = deferred();
  const transport = accountTransport({
    execute: () => {
      calls++;
      return next.promise;
    },
    expected: { ...session },
    readSession: () => session,
    alive: () => alive,
    onUnauthenticated: () => {
      expired++;
    },
  });
  return {
    transport,
    next,
    setSession: (value: AccountSession) => {
      session = value;
    },
    close: () => {
      alive = false;
    },
    get calls() {
      return calls;
    },
    get expired() {
      return expired;
    },
  };
}
const changed = (error: unknown) =>
  error instanceof BackendError && error.code === "session_changed";
test("closed account scopes never dispatch retained requests", async () => {
  const f = fixture();
  f.setSession({ accountId: null, epoch: 2, active: false });
  await assert.rejects(f.transport({ op: "spec.publish" }), changed);
  assert.equal(f.calls, 0);
});
test("a late committed response cannot enter another account and keeps outcome uncertain", async () => {
  const f = fixture(),
    request = f.transport({ op: "spec.publish" });
  f.setSession({ accountId: "bob", epoch: 2, active: true });
  f.next.resolve({ app: { privateDraft: "alice" } });
  await assert.rejects(
    request,
    (error: unknown) => changed(error) && (error as BackendError).uncertain,
  );
});
test("same-account sign-out and sign-in invalidates the original epoch", async () => {
  const f = fixture(),
    request = f.transport({ op: "spec.getApp" });
  f.setSession({ accountId: "alice", epoch: 3, active: true });
  f.next.resolve({ app: "private" });
  await assert.rejects(request, changed);
});
test("late unauthorized responses cannot sign out a replacement account", async () => {
  const f = fixture(),
    request = f.transport({ op: "spec.getApp" });
  f.setSession({ accountId: "bob", epoch: 2, active: true });
  f.next.reject(
    new BackendError("Expired", "expired", "unauthenticated", false, 401),
  );
  await assert.rejects(request, changed);
  assert.equal(f.expired, 0);
});
test("current unauthorized response expires its account; app-only denial does not", async () => {
  for (const status of [401, 403, 404]) {
    const f = fixture(),
      request = f.transport({ op: "spec.getApp" });
    f.next.reject(
      new BackendError(
        "Denied",
        "denied",
        status === 401 ? "unauthenticated" : "service",
        false,
        status,
      ),
    );
    await assert.rejects(
      request,
      (error: unknown) =>
        error instanceof BackendError && error.status === status,
    );
    assert.equal(f.expired, status === 401 ? 1 : 0);
  }
});
test("scope disposal suppresses a settled result even if the account remains signed in", async () => {
  const f = fixture(),
    request = f.transport({ op: "spec.getApp" });
  f.close();
  f.next.resolve({ app: "private" });
  await assert.rejects(request, changed);
});
