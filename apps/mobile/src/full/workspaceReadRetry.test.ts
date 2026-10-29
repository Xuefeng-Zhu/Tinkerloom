import assert from "node:assert/strict";
import test from "node:test";
import {
  AppwriteBackend,
  type ExecutionResult,
  type SdkAdapter,
} from "../backend/core";
import { BackendError } from "../backend/errors";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { accountTransport } from "./FullRegistry";
import { FullWorkspaceController } from "./FullWorkspaceController";
import { fullTemplates } from "./catalog";

const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "workspace_workspace",
};
const spec = fullTemplates.find((template) => template.id === "planner")!.spec;
function completed(value: unknown, status: unknown = 200): ExecutionResult {
  return {
    status: "completed",
    responseStatusCode: status,
    responseBody: JSON.stringify(value),
  };
}
const conflict = () => completed({ error: "transaction_conflict" }, 409);
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((yes) => {
    resolve = yes;
  });
  return { promise, resolve };
}
function summary(id = "version_1", number = 1) {
  return {
    id,
    number,
    hash: `hash_${id}`,
    name: "Planner",
    theme: "teal",
    icon: "book",
    publisherId: "alice",
    createdAt: null,
  };
}
function app(id: string, pinned = false) {
  return {
    id,
    workspaceId: "workspace",
    name: id,
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    pinned,
    pinRevision: 1,
    recordCount: 0,
    availablePlaces: null,
    version: null,
  };
}
function draft(appId: string) {
  return {
    appId,
    workspaceId: "workspace",
    name: appId,
    engine: "appspec.v1",
    revision: 1,
    stale: false,
    updatedAt: null,
  };
}
function fixture() {
  let ids = 0,
    session = { accountId: "alice" as string | null, epoch: 1, active: true };
  let catalog = [app("old_app")],
    drafts = [draft("old_draft")];
  const saved = new Map<string, string>(),
    requests: Record<string, unknown>[] = [],
    wires: string[] = [],
    counts = new Map<string, number>();
  let respond:
    | ((
        request: Record<string, unknown>,
        count: number,
      ) => ExecutionResult | null | Promise<ExecutionResult | null>)
    | null = null;
  let intercept:
    ((request: Record<string, unknown>) => Promise<unknown>) | null = null;
  const host = hostStores(new HostLifetime(scope), {
    async read(key) {
      return saved.get(key) ?? null;
    },
    async change(key, update) {
      const next = update(saved.get(key) ?? null);
      if (next === null) saved.delete(key);
      else saved.set(key, next);
    },
  });
  const sdk: SdkAdapter = {
    newId: () => `operation_${++ids}`,
    account: {
      get: async () => null,
      create: async () => null,
      createEmailPasswordSession: async () => null,
      deleteSession: async () => null,
    },
    async execute(wire) {
      wires.push(wire);
      const request = JSON.parse(wire),
        op = String(request.op),
        count = (counts.get(op) ?? 0) + 1;
      counts.set(op, count);
      if (respond) {
        const result = await respond(request, count);
        if (result) return result;
      }
      if (op === "spec.launcher")
        return completed({
          apps: catalog.filter((row) => !request.pinnedOnly || row.pinned),
          nextCursor: null,
        });
      if (op === "spec.listDrafts")
        return completed({ drafts, nextCursor: null });
      if (op === "spec.listVersions")
        return completed({ versions: [summary()], nextBeforeNumber: null });
      if (op === "spec.getVersion")
        return completed({
          version: { ...summary(String(request.versionId)), spec },
        });
      if (["spec.instantiate", "spec.createApp", "spec.remix"].includes(op)) {
        const id = String(request.id);
        catalog = [...catalog, app(id)];
        return completed({
          app: {
            id,
            workspaceId: "workspace",
            name: "Created planner",
            engine: "appspec.v1",
            role: "owner",
            archived: false,
            capabilities: { editDefinition: true },
            controlRevision: 1,
            allowedActions: [],
            version: {
              id: "published_1",
              number: 1,
              hash: "version_hash",
              spec,
            },
            draft: null,
            generation: null,
          },
        });
      }
      if (op === "spec.setPinned")
        return completed({
          shortcut: {
            appId: request.appId,
            pinned: request.pinned,
            revision: Number(request.expectedRevision) + 1,
          },
        });
      if (op === "spec.capabilities")
        return completed({
          apiVersion: 1,
          formatVersions: [1],
          generation: false,
          guidance: true,
          effects: [],
          privateMedia: false,
        });
      if (op === "spec.guidance") return completed({ questions: [] });
      assert.fail(`Unexpected request ${op}`);
    },
  };
  const backend = new AppwriteBackend(sdk);
  const transport = accountTransport({
    execute: async (request) =>
      intercept ? intercept(request) : backend.executeSpec(request),
    readSession: () => session,
    expected: { ...session },
    alive: () => host.lifetime.active,
    onUnauthenticated() {
      host.lifetime.dispose();
    },
  });
  const controller = new FullWorkspaceController({
    scope,
    workspaceId: "workspace",
    host,
    newId: () => backend.newId(),
    transport: (request) => {
      requests.push(request);
      return transport(request);
    },
  });
  return {
    controller,
    host,
    saved,
    requests,
    wires,
    counts,
    get ids() {
      return ids;
    },
    set respond(value: typeof respond) {
      respond = value;
    },
    set intercept(value: typeof intercept) {
      intercept = value;
    },
    set catalog(value: typeof catalog) {
      catalog = value;
    },
    set drafts(value: typeof drafts) {
      drafts = value;
    },
    flipAccount() {
      session = { accountId: "bob", epoch: 2, active: true };
    },
    expireAccount() {
      session = { accountId: null, epoch: 2, active: false };
      host.lifetime.dispose();
    },
  };
}
const pause = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

test("a confirmed instantiate ACK survives read conflicts and refreshes the launcher without resubmitting creation", async () => {
  const f = fixture();
  await f.controller.load();
  let postCreationLauncher = 0;
  f.respond = (request) => {
    if (request.op === "spec.launcher" && ++postCreationLauncher <= 2)
      return conflict();
    return null;
  };
  await f.controller.instantiate("planner");
  const state = f.controller.getSnapshot();
  assert.equal(state.createdAppId, "operation_1");
  assert.equal(state.pending, null);
  assert.equal(state.error, null);
  assert.equal(state.loading, false);
  assert.equal(state.busy, false);
  assert.deepEqual(
    state.apps.map((row) => row.id),
    ["old_app", "operation_1"],
  );
  assert.equal(f.counts.get("spec.instantiate"), 1);
  assert.equal(postCreationLauncher, 3);
  assert.equal(f.ids, 2);
  assert.equal(f.saved.size, 0);
  const attempts = f.requests
    .filter((request) => request.op === "spec.launcher")
    .slice(1);
  assert.equal(new Set(attempts).size, 1);
  assert.ok(attempts.every(Object.isFrozen));
  assert.equal(
    new Set(
      f.wires
        .filter((wire) => JSON.parse(wire).op === "spec.launcher")
        .slice(1),
    ).size,
    1,
  );
  f.controller.dispose();
});
test("exhausted post-create reads make exactly three attempts and preserve the successful created result and cleared journal", async () => {
  const f = fixture();
  await f.controller.load();
  f.respond = (request) => (request.op === "spec.launcher" ? conflict() : null);
  await f.controller.instantiate("planner");
  const state = f.controller.getSnapshot();
  assert.equal(state.createdAppId, "operation_1");
  assert.equal(state.pending, null);
  assert.equal(state.pendingStatus, null);
  assert.match(state.error!, /same time/);
  assert.deepEqual(
    state.apps.map((row) => row.id),
    ["old_app"],
  );
  assert.equal(f.counts.get("spec.launcher"), 4);
  assert.equal(f.counts.get("spec.instantiate"), 1);
  assert.equal(f.ids, 2);
  assert.equal(f.saved.size, 0);
  f.controller.dispose();
});
test("draft pages, version history and immutable-version reads use at most two extra attempts with frozen identical parameters", async () => {
  for (const op of [
    "spec.listDrafts",
    "spec.listVersions",
    "spec.getVersion",
  ]) {
    const f = fixture();
    f.respond = (request, count) =>
      request.op === op && count <= 2 ? conflict() : null;
    if (op === "spec.listDrafts") await f.controller.load();
    else if (op === "spec.listVersions") await f.controller.history("old_app");
    else await f.controller.inspectVersion("old_app", "version_2");
    assert.equal(f.counts.get(op), 3);
    assert.equal(f.controller.getSnapshot().error, null);
    if (op === "spec.listDrafts")
      assert.equal(f.controller.getSnapshot().drafts[0].appId, "old_draft");
    else if (op === "spec.listVersions")
      assert.equal(f.controller.getSnapshot().versions[0].id, "version_1");
    else
      assert.equal(
        f.controller.getSnapshot().historical?.summary.id,
        "version_2",
      );
    const attempts = f.requests.filter((request) => request.op === op);
    assert.equal(new Set(attempts).size, 1);
    assert.ok(attempts.every(Object.isFrozen));
    assert.equal(
      new Set(f.wires.filter((wire) => JSON.parse(wire).op === op)).size,
      1,
    );
    assert.equal(f.ids, 0);
    f.controller.dispose();
  }
});
test("pagination retries retain the original server filter and cursor, including draft and history cursors", async () => {
  for (const kind of ["apps", "drafts", "history"] as const) {
    const f = fixture();
    f.respond = (request) => {
      if (request.op === "spec.launcher")
        return completed({
          apps: [app("pin_1", true)],
          nextCursor: "pinned_cursor",
        });
      if (request.op === "spec.listDrafts")
        return completed({
          drafts: [draft("draft_1")],
          nextCursor: "draft_cursor",
        });
      if (request.op === "spec.listVersions")
        return completed({
          versions: [summary("version_8", 8)],
          nextBeforeNumber: 8,
        });
      return null;
    };
    if (kind === "history") await f.controller.history("old_app");
    else await f.controller.setPinnedOnly(true);
    let pages = 0;
    const op =
      kind === "apps"
        ? "spec.launcher"
        : kind === "drafts"
          ? "spec.listDrafts"
          : "spec.listVersions";
    f.respond = (request) => {
      assert.equal(request.op, op);
      if (++pages === 1) return conflict();
      return completed(
        kind === "apps"
          ? { apps: [app("pin_2", true)], nextCursor: null }
          : kind === "drafts"
            ? { drafts: [draft("draft_2")], nextCursor: null }
            : { versions: [summary("version_7", 7)], nextBeforeNumber: null },
      );
    };
    if (kind === "history") await f.controller.history("old_app", true);
    else await f.controller.loadMore(kind);
    const attempts = f.requests
      .filter((request) => request.op === op)
      .slice(-2);
    assert.equal(pages, 2);
    assert.equal(attempts[0], attempts[1]);
    assert.ok(Object.isFrozen(attempts[0]));
    if (kind === "history") assert.equal(attempts[0].beforeNumber, 8);
    else
      assert.equal(
        attempts[0].cursor,
        kind === "apps" ? "pinned_cursor" : "draft_cursor",
      );
    if (kind === "apps") assert.equal(attempts[0].pinnedOnly, true);
    else assert.equal(Object.hasOwn(attempts[0], "pinnedOnly"), false);
    assert.equal(f.controller.getSnapshot().error, null);
    assert.equal(f.ids, 0);
    f.controller.dispose();
  }
});
test("unknown, malformed, uncertain, cursor/revision and authority errors never enter the conflict retry path", async () => {
  const cases: { sdk?: ExecutionResult; error?: unknown; direct?: boolean }[] =
    [
      { error: new Error("Transport interrupted") },
      {
        error: {
          kind: "service",
          status: 409,
          code: "transaction_conflict",
          uncertain: false,
        },
        direct: true,
      },
      {
        error: new BackendError(
          "Unknown",
          "transaction_conflict",
          "service",
          true,
          409,
        ),
        direct: true,
      },
      {
        error: new BackendError(
          "Wrong kind",
          "transaction_conflict",
          "transport",
          false,
          409,
        ),
        direct: true,
      },
      {
        error: Object.assign(
          new BackendError(
            "Missing certainty",
            "transaction_conflict",
            "service",
            false,
            409,
          ),
          { uncertain: undefined },
        ),
        direct: true,
      },
      {
        error: Object.assign(
          new BackendError(
            "Wrong certainty",
            "transaction_conflict",
            "service",
            false,
            409,
          ),
          { uncertain: 0 },
        ),
        direct: true,
      },
      {
        error: new BackendError(
          "Wrong status",
          "transaction_conflict",
          "service",
          false,
          "409" as unknown as number,
        ),
        direct: true,
      },
      { sdk: completed({ error: "cursor_invalid" }, 409) },
      { sdk: completed({ error: "revision_conflict" }, 409) },
      { sdk: completed({ error: "transaction_conflict" }, 403) },
      { sdk: completed({ error: "transaction_conflict" }, 404) },
      { sdk: completed({ error: "transaction_conflict" }, 500) },
      { sdk: completed({ error: "transaction_conflict" }, "409") },
      {
        sdk: {
          status: "processing",
          responseStatusCode: 409,
          responseBody: '{"error":"transaction_conflict"}',
        },
      },
      {
        sdk: {
          status: "completed",
          responseStatusCode: 409,
          responseBody: "{",
        },
      },
      { sdk: completed({ error: { code: "transaction_conflict" } }, 409) },
      { sdk: completed({ error: "transaction_conflict" }) },
      { sdk: completed({ apps: "malformed", nextCursor: null }) },
    ];
  for (const scenario of cases) {
    const f = fixture();
    if (scenario.direct)
      f.intercept = async () => {
        throw scenario.error;
      };
    else
      f.respond = () => {
        if (scenario.error) throw scenario.error;
        return scenario.sdk!;
      };
    await f.controller.load();
    assert.equal(f.requests.length, 1);
    assert.deepEqual(f.controller.getSnapshot().apps, []);
    assert.ok(f.controller.getSnapshot().error);
    assert.equal(f.ids, 0);
    f.controller.dispose();
  }
});
test("filter replacement or cursor refresh cancels old backoff and fences late success or denial without overriding new authority", async () => {
  for (const replacement of ["filter", "refresh"] as const) {
    for (const phase of ["backoff", "late-success", "late-denial"] as const) {
      const f = fixture(),
        entered = deferred<void>(),
        late = deferred<ExecutionResult>();
      f.respond = (request) =>
        request.op === "spec.launcher"
          ? completed({ apps: [app("recent")], nextCursor: "old_cursor" })
          : null;
      await f.controller.load();
      f.respond = (request) => {
        if (request.op === "spec.launcher" && request.cursor) {
          entered.resolve();
          return phase === "backoff" ? conflict() : late.promise;
        }
        if (request.op === "spec.launcher")
          return completed({
            apps: [app("current_pin", true)],
            nextCursor: "new_cursor",
          });
        return null;
      };
      const old = f.controller.loadMore("apps");
      await entered.promise;
      if (phase === "backoff") await pause(10);
      if (replacement === "filter") await f.controller.setPinnedOnly(true);
      else await f.controller.load();
      late.resolve(
        phase === "late-denial"
          ? completed({ error: "forbidden" }, 403)
          : completed({ apps: [app("stale")], nextCursor: "stale_cursor" }),
      );
      await old;
      assert.deepEqual(
        f.controller.getSnapshot().apps.map((row) => row.id),
        ["current_pin"],
      );
      assert.equal(f.controller.getSnapshot().cursor, "new_cursor");
      assert.equal(f.controller.getSnapshot().error, null);
      assert.equal(f.controller.getSnapshot().accessLost, false);
      assert.equal(
        f.wires.filter((wire) => JSON.parse(wire).cursor === "old_cursor")
          .length,
        1,
      );
      f.controller.dispose();
    }
  }
});
test("history replacement and closing its version inspector stop retries and late stale access failures", async () => {
  for (const close of [false, true]) {
    const f = fixture(),
      entered = deferred<void>(),
      late = deferred<ExecutionResult>();
    f.respond = (request) => {
      if (request.op === "spec.getVersion") {
        entered.resolve();
        return close ? conflict() : late.promise;
      }
      return null;
    };
    const old = f.controller.inspectVersion("old_app", "old_version");
    await entered.promise;
    if (close) {
      await pause(10);
      f.controller.closeHistorical();
    } else await f.controller.history("new_app");
    late.resolve(completed({ error: "forbidden" }, 403));
    await old;
    assert.equal(f.counts.get("spec.getVersion"), 1);
    assert.equal(f.controller.getSnapshot().accessLost, false);
    assert.equal(f.controller.getSnapshot().error, null);
    assert.equal(f.controller.getSnapshot().historical, null);
    if (!close)
      assert.equal(f.controller.getSnapshot().historyAppId, "new_app");
    f.controller.dispose();
  }
});
test("disposal, lifetime loss and an account flip during backoff prevent extra SDK requests", async () => {
  for (const interruption of ["dispose", "lifetime", "account"] as const) {
    const f = fixture(),
      entered = deferred<void>();
    f.respond = () => {
      entered.resolve();
      return conflict();
    };
    const reading = f.controller.load();
    await entered.promise;
    await pause(10);
    if (interruption === "dispose") f.controller.dispose();
    else if (interruption === "lifetime") f.expireAccount();
    else f.flipAccount();
    await reading;
    assert.equal(f.wires.length, 1);
    assert.deepEqual(f.controller.getSnapshot().apps, []);
    if (interruption === "account")
      assert.equal(f.controller.getSnapshot().accessLost, true);
    f.controller.dispose();
  }
});
test("a current authority denial after conflict clears workspace private state instead of retrying the denial", async () => {
  for (const status of [403, 404]) {
    const f = fixture();
    await f.controller.load();
    f.controller.setPlannedIdea("Private unsent idea");
    let tries = 0;
    f.respond = (request) =>
      request.op === "spec.launcher"
        ? ++tries === 1
          ? conflict()
          : completed(
              { error: status === 403 ? "forbidden" : "not_found" },
              status,
            )
        : null;
    await f.controller.load();
    const state = f.controller.getSnapshot();
    assert.equal(tries, 2);
    assert.equal(state.accessLost, true);
    assert.deepEqual(state.apps, []);
    assert.deepEqual(state.drafts, []);
    assert.equal(state.plannedIdea, "");
    assert.equal(state.createdAppId, null);
    assert.equal(state.pending, null);
    f.controller.dispose();
  }
});
test("mutations and clarification provider calls never use read retries or replace retained operation IDs", async () => {
  for (const op of [
    "spec.instantiate",
    "spec.createApp",
    "spec.remix",
    "spec.setPinned",
    "spec.guidance",
    "spec.capabilities",
  ]) {
    const f = fixture();
    await f.controller.load();
    f.respond = (request) => (request.op === op ? conflict() : null);
    if (op === "spec.instantiate") await f.controller.instantiate("planner");
    else if (op === "spec.createApp") await f.controller.create("A shell");
    else if (op === "spec.remix")
      await f.controller.remix("old_app", "version_1");
    else if (op === "spec.setPinned")
      await f.controller.setPinned(f.controller.getSnapshot().apps[0], true);
    else await f.controller.requestGuidance("Help me plan a week");
    assert.equal(f.counts.get(op), 1);
    if (
      op.startsWith("spec.") &&
      !["spec.guidance", "spec.capabilities"].includes(op)
    ) {
      const pending = f.controller.getSnapshot().pending;
      assert.equal(pending?.request.op, op);
      assert.equal(f.controller.getSnapshot().pendingStatus, "uncertain");
      assert.equal(
        pending?.request.operationId,
        op === "spec.setPinned" ? "operation_1" : "operation_2",
      );
      assert.ok(f.saved.size > 0);
    } else {
      assert.equal(f.ids, 0);
      assert.equal(f.saved.size, 0);
    }
    f.controller.dispose();
  }
});

test("caller-side attempts to alter a captured page request cannot change its filter, cursor or bytes on retry", async () => {
  const f = fixture(),
    entered = deferred<void>();
  f.respond = (request) =>
    request.op === "spec.launcher"
      ? completed({ apps: [app("pin_1", true)], nextCursor: "captured_cursor" })
      : null;
  await f.controller.setPinnedOnly(true);
  let pages = 0;
  f.respond = () => {
    if (++pages === 1) {
      entered.resolve();
      return conflict();
    }
    return completed({ apps: [app("pin_2", true)], nextCursor: null });
  };
  const more = f.controller.loadMore("apps");
  await entered.promise;
  const captured = f.requests.at(-1)!;
  assert.ok(Object.isFrozen(captured));
  assert.equal(Reflect.set(captured, "cursor", "foreign_cursor"), false);
  assert.equal(Reflect.set(captured, "pinnedOnly", false), false);
  assert.equal(Reflect.set(captured, "workspaceId", "other_workspace"), false);
  await more;
  const attempts = f.requests.filter((request) => request.cursor);
  assert.equal(attempts.length, 2);
  assert.equal(attempts[0], attempts[1]);
  assert.equal(attempts[1].cursor, "captured_cursor");
  assert.equal(attempts[1].pinnedOnly, true);
  assert.equal(attempts[1].workspaceId, "workspace");
  assert.equal(
    new Set(f.wires.filter((wire) => JSON.parse(wire).cursor)).size,
    1,
  );
  assert.deepEqual(
    f.controller.getSnapshot().apps.map((row) => row.id),
    ["pin_1", "pin_2"],
  );
  assert.equal(f.ids, 0);
  f.controller.dispose();
});
test("an account flip or disposal while a SDK read is in flight fences late private rows and late denial", async () => {
  for (const outcome of ["success", "denial"] as const) {
    for (const interruption of ["account", "dispose"] as const) {
      const f = fixture(),
        entered = deferred<void>(),
        response = deferred<ExecutionResult>();
      await f.controller.load();
      f.respond = () => {
        entered.resolve();
        return response.promise;
      };
      const reading = f.controller.load();
      await entered.promise;
      if (interruption === "account") f.flipAccount();
      else f.controller.dispose();
      response.resolve(
        outcome === "success"
          ? completed({ apps: [app("late_private_app")], nextCursor: null })
          : completed({ error: "forbidden" }, 403),
      );
      await reading;
      assert.deepEqual(f.controller.getSnapshot().apps, []);
      assert.deepEqual(f.controller.getSnapshot().drafts, []);
      assert.equal(f.counts.get("spec.launcher"), 2);
      assert.equal(f.ids, 0);
      f.controller.dispose();
    }
  }
});
