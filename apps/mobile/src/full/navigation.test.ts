import assert from "node:assert/strict";
import test from "node:test";
import {
  FullRouteVisits,
  NavigationEpoch,
  fullRouteParams,
  guardHostNavigation,
  parseFullRoute,
} from "./navigation";
import type { NavigationSource } from "./navigation";

const entry = { pageId: "todayPage" };
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((yes) => {
    resolve = yes;
  });
  return { promise, resolve };
}
function source() {
  const hostState = {
    pending: null as unknown,
    busy: false,
    dirty: false,
    editorError: null as unknown,
  };
  const runtimeState = { pending: null as unknown, dirty: false };
  const lifetime = { active: true };
  let flushes = 0;
  const value: NavigationSource = {
    getSnapshot: () => hostState,
    runtime: { getSnapshot: () => runtimeState },
    host: { lifetime },
    flush: async () => {
      ++flushes;
      hostState.dirty = false;
      return true;
    },
  };
  return { value, hostState, runtimeState, lifetime, flushes: () => flushes };
}
test("full routes accept identities only and canonical serialization clears obsolete edit/query state", () => {
  const request = parseFullRoute({
    page: "taskEditorPage",
    recordId: "record_1",
    edit: "true",
    mode: "live",
  });
  assert.equal(request.error, null);
  assert.deepEqual(request.location, {
    pageId: "taskEditorPage",
    recordId: "record_1",
    editing: true,
  });
  assert.deepEqual(fullRouteParams("app_1", entry, "live"), {
    appId: "app_1",
    page: "todayPage",
    recordId: undefined,
    edit: undefined,
    mode: undefined,
  });
  assert.deepEqual(parseFullRoute({}).location, {});
  assert.equal(
    fullRouteParams("app_1", { pageId: "__legacy__" }, "build").page,
    undefined,
  );
  for (const params of [
    { page: ["todayPage", "tasksPage"] },
    { recordId: "../private" },
    { recordId: "x".repeat(37) },
    { edit: "true" },
    { edit: "false" },
    { mode: ["live"] },
    { mode: "owner" },
    { page: "a/b" },
  ])
    assert.ok(parseFullRoute(params).error);
  const extras = {
    recordId: "record_1",
    role: "owner",
    revision: 99,
    data: { title: "Untrusted" },
  };
  assert.deepEqual(parseFullRoute(extras).location, { recordId: "record_1" });
});
test("only previously observed entries within the same controller can be native/browser return parents", () => {
  const visits = new FullRouteVisits(),
    otherAccount = new FullRouteVisits();
  visits.remember("route_1", entry, "live");
  assert.equal(visits.owns("route_1", entry, "live"), true);
  assert.equal(
    visits.owns("route_1", { pageId: "todayPage", recordId: "r1" }, "live"),
    false,
  );
  assert.equal(visits.owns("route_1", entry, "build"), false);
  assert.equal(visits.owns("foreign_key", entry, "live"), false);
  assert.equal(otherAccount.owns("route_1", entry, "live"), false);
});
test("guard leaves dirty forms intact until explicit discard acceptance, then repeats the original action", async () => {
  const s = source(),
    epoch = new NavigationEpoch();
  s.runtimeState.dirty = true;
  let accept: (() => void) | null = null,
    actions = 0,
    releases = 0;
  await guardHostNavigation({
    source: s.value,
    epoch,
    focused: () => true,
    action: () => ++actions,
    beforeNavigate: () => ++releases,
    prompt: (callback) => {
      accept = callback;
    },
    blocked: () => assert.fail("not locked"),
  });
  assert.equal(actions, 0);
  assert.equal(s.runtimeState.dirty, true);
  assert.equal(releases, 0);
  assert.ok(accept);
  s.runtimeState.dirty = false;
  (accept as () => void)();
  assert.equal(actions, 1);
  assert.equal(releases, 1);
});
test("host/record unresolved commands and busy writes never flush, discard or repeat a browser removal", async () => {
  for (const which of ["host", "runtime", "busy"] as const) {
    const s = source();
    s.hostState.dirty = true;
    if (which === "host") s.hostState.pending = { operationId: "retained" };
    if (which === "runtime")
      s.runtimeState.pending = { command: "exact original" };
    if (which === "busy") s.hostState.busy = true;
    let blocked = 0;
    await guardHostNavigation({
      source: s.value,
      epoch: new NavigationEpoch(),
      focused: () => true,
      action: () => assert.fail("locked action"),
      prompt: () => assert.fail("locked prompt"),
      blocked: () => ++blocked,
    });
    assert.equal(blocked, 1);
    assert.equal(s.flushes(), 0);
    assert.equal(s.hostState.dirty, true);
  }
});
test("delayed draft flush and discard callbacks cannot navigate after blur, account disposal, newer request or a new pending command", async () => {
  for (const interruption of ["blur", "dispose", "newer", "pending"] as const) {
    const s = source(),
      epoch = new NavigationEpoch(),
      wait = deferred<boolean>();
    s.hostState.dirty = true;
    s.value.flush = () => wait.promise;
    let focused = true,
      actions = 0;
    const task = guardHostNavigation({
      source: s.value,
      epoch,
      focused: () => focused,
      action: () => ++actions,
      prompt: (accept) => accept(),
      blocked: () => {},
    });
    if (interruption === "blur") focused = false;
    if (interruption === "dispose") s.lifetime.active = false;
    if (interruption === "newer") epoch.next();
    if (interruption === "pending")
      s.runtimeState.pending = { operationId: "unknown" };
    wait.resolve(true);
    await task;
    assert.equal(actions, 0, interruption);
  }
  const s = source(),
    epoch = new NavigationEpoch();
  s.runtimeState.dirty = true;
  let accept!: () => void,
    actions = 0;
  await guardHostNavigation({
    source: s.value,
    epoch,
    focused: () => true,
    action: () => ++actions,
    prompt: (callback) => {
      accept = callback;
    },
    blocked: () => {},
  });
  s.runtimeState.pending = { operationId: "uncertain" };
  accept();
  assert.equal(actions, 0);
  epoch.cancel();
  s.runtimeState.pending = null;
  accept();
  assert.equal(actions, 0);
});
test("failed draft flush never switches mode or leaves the current URL", async () => {
  const s = source();
  s.hostState.editorError = "invalid spec";
  s.value.flush = async () => false;
  await guardHostNavigation({
    source: s.value,
    epoch: new NavigationEpoch(),
    focused: () => true,
    action: () => assert.fail("invalid draft navigation"),
    prompt: () => assert.fail("invalid draft prompt"),
    blocked: () => {},
  });
});

test("Forward/PUSH plans return to the exact dirty source visit without transferring ownership to a fresh form", () => {
  const visits = new FullRouteVisits(),
    otherScope = new FullRouteVisits();
  let changes = 0;
  const stop = visits.subscribe(() => ++changes);
  visits.protect("original_form", true);
  visits.protect("fresh_forward_visit", true);
  assert.equal(visits.getProtection().ownerKey, "original_form");
  assert.equal(
    visits.protectedReturnCount("fresh_forward_visit", [
      "launcher",
      "original_form",
      "intermediate",
      "fresh_forward_visit",
    ]),
    2,
  );
  assert.equal(
    visits.protectedReturnCount("original_form", ["launcher", "original_form"]),
    0,
  );
  assert.equal(
    visits.protectedReturnCount("fresh_forward_visit", [
      "launcher",
      "fresh_forward_visit",
    ]),
    null,
  );
  assert.equal(
    visits.protectedReturnCount("not_focused", [
      "original_form",
      "not_focused",
      "current",
    ]),
    null,
  );
  assert.equal(otherScope.getProtection().ownerKey, null);
  assert.equal(changes, 1);
  stop();
});
test("a deferred Forward intent retains owner identity; Keep editing clears intent without releasing the dirty source", () => {
  const visits = new FullRouteVisits();
  visits.protect("editor_route", true);
  const request = parseFullRoute({ page: "tasksPage" });
  visits.defer(request);
  const attempt = visits.getProtection().attempt!;
  assert.equal(attempt.route, request);
  visits.dismissAttempt(attempt.id + 1);
  assert.equal(visits.getProtection().attempt, attempt);
  visits.dismissAttempt(attempt.id);
  assert.equal(visits.getProtection().attempt, null);
  assert.equal(visits.getProtection().ownerKey, "editor_route");
  visits.protect("editor_route", false);
  assert.equal(visits.getProtection().ownerKey, null);
});
test("cleaning a form does not silently consume or replace the exact deferred navigation request", () => {
  const visits = new FullRouteVisits();
  visits.protect("editor_route", true);
  visits.defer(parseFullRoute({ page: "taskDetailPage", recordId: "r1" }));
  const first = visits.getProtection().attempt!;
  visits.protect("editor_route", false);
  assert.equal(visits.getProtection().attempt, first);
  visits.defer(parseFullRoute({ page: "tasksPage" }));
  const latest = visits.getProtection().attempt!;
  assert.ok(latest.id > first.id);
  visits.dismissAttempt(first.id);
  assert.equal(visits.getProtection().attempt, latest);
  visits.dismissAttempt(latest.id);
  assert.equal(visits.getProtection().attempt, null);
});
