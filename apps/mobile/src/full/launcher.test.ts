import assert from "node:assert/strict";
import { createRequire, registerHooks } from "node:module";
import test from "node:test";
import { createElement, type ReactNode } from "react";
import { BackendError } from "../backend/errors";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { RuntimeError } from "../runtime/errors";
import {
  FullWorkspaceController,
  type LauncherApp,
  type WorkspaceState,
} from "./FullWorkspaceController";

const { renderToStaticMarkup } = createRequire(import.meta.url)(
  "react-dom/server",
) as {
  renderToStaticMarkup(element: ReactNode): string;
};

const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "workspace_workspace",
};
function makeController(
  transport: (request: Record<string, unknown>) => Promise<unknown>,
) {
  const saved = new Map<string, string>();
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
  let id = 0;
  return new FullWorkspaceController({
    scope,
    workspaceId: "workspace",
    transport,
    host,
    newId: () => `operation_${++id}`,
  });
}
function app(id: string, pinned = false, pinRevision = 1): LauncherApp {
  return {
    id,
    workspaceId: "workspace",
    name: id,
    engine: "appspec.v1",
    role: "viewer",
    archived: false,
    pinned,
    pinRevision,
    recordCount: 0,
    availablePlaces: null,
    version: null,
  };
}
const emptyDrafts = { drafts: [], nextCursor: null };
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

test("pinned catalog is queried beyond the loaded unfiltered page and every cursor keeps its filter", async () => {
  const requests: Record<string, unknown>[] = [];
  const controller = makeController(async (request) => {
    requests.push(request);
    if (request.op === "spec.listDrafts") return emptyDrafts;
    if (!request.pinnedOnly)
      return { apps: [app("new_unpinned")], nextCursor: "all_cursor" };
    return request.cursor
      ? { apps: [app("older_pinned_2", true)], nextCursor: null }
      : { apps: [app("older_pinned_1", true)], nextCursor: "pin_cursor" };
  });
  await controller.load();
  await controller.setPinnedOnly(true);
  assert.deepEqual(
    controller.getSnapshot().apps.map((v) => v.id),
    ["older_pinned_1"],
  );
  await controller.loadMore("apps");
  assert.deepEqual(
    controller.getSnapshot().apps.map((v) => v.id),
    ["older_pinned_1", "older_pinned_2"],
  );
  const launcher = requests.filter((v) => v.op === "spec.launcher");
  assert.deepEqual(
    launcher.map((v) => [v.pinnedOnly, v.cursor ?? null]),
    [
      [false, null],
      [true, null],
      [true, "pin_cursor"],
    ],
  );
  assert.ok(
    requests
      .filter((v) => v.op === "spec.listDrafts")
      .every((v) => !Object.hasOwn(v, "pinnedOnly")),
  );
  assert.equal(controller.getSnapshot().cursor, null);
  controller.dispose();
});

for (const outcome of ["success", "failure"] as const) {
  test(`filter replacement fences late ${outcome} from a previous pagination request`, async () => {
    const oldPage = deferred<unknown>();
    const controller = makeController(async (request) => {
      if (request.op === "spec.listDrafts") return emptyDrafts;
      if (request.cursor) return oldPage.promise;
      return {
        apps: [
          app(request.pinnedOnly ? "pinned" : "recent", !!request.pinnedOnly),
        ],
        nextCursor: request.pinnedOnly ? null : "old_cursor",
      };
    });
    await controller.load();
    const more = controller.loadMore("apps");
    const changing = controller.setPinnedOnly(true);
    assert.equal(controller.getSnapshot().cursor, null);
    assert.deepEqual(controller.getSnapshot().apps, []);
    await changing;
    if (outcome === "success")
      oldPage.resolve({ apps: [app("stale")], nextCursor: "stale_cursor" });
    else
      oldPage.reject(new RuntimeError("revision_conflict", "Old page changed"));
    await more;
    assert.deepEqual(
      controller.getSnapshot().apps.map((v) => v.id),
      ["pinned"],
    );
    assert.equal(controller.getSnapshot().error, null);
    assert.equal(controller.getSnapshot().loading, false);
    controller.dispose();
  });
}

test("rapid filter changes fence old initial reads and refresh starts again with the active filter", async () => {
  const stale = deferred<unknown>();
  const requests: Record<string, unknown>[] = [];
  let first = true;
  const controller = makeController(async (request) => {
    requests.push(request);
    if (request.op === "spec.listDrafts") return emptyDrafts;
    if (first) {
      first = false;
      return stale.promise;
    }
    return { apps: [app("pin", true)], nextCursor: "pin_page_2" };
  });
  const initial = controller.load();
  await controller.setPinnedOnly(true);
  stale.resolve({ apps: [app("stale_recent")], nextCursor: "all_page_2" });
  await initial;
  await controller.load();
  assert.deepEqual(
    controller.getSnapshot().apps.map((v) => v.id),
    ["pin"],
  );
  assert.ok(
    requests
      .filter((v) => v.op === "spec.launcher")
      .slice(1)
      .every((v) => v.pinnedOnly === true && !Object.hasOwn(v, "cursor")),
  );
  assert.equal(controller.getSnapshot().cursor, "pin_page_2");
  controller.dispose();
});

test("filtered catalog rejects unpinned entries and foreign workspace pages without appending", async () => {
  let response: unknown = { apps: [app("recent")], nextCursor: "cursor" };
  const controller = makeController(async (request) =>
    request.op === "spec.listDrafts" ? emptyDrafts : response,
  );
  await controller.load();
  response = { apps: [app("wrong", false)], nextCursor: null };
  await controller.setPinnedOnly(true);
  assert.deepEqual(controller.getSnapshot().apps, []);
  assert.match(controller.getSnapshot().error!, /unpinned/);
  response = { apps: [app("pin", true)], nextCursor: "pin_cursor" };
  await controller.load();
  response = {
    apps: [{ ...app("foreign", true), workspaceId: "foreign" }],
    nextCursor: null,
  };
  await controller.loadMore("apps");
  assert.deepEqual(
    controller.getSnapshot().apps.map((v) => v.id),
    ["pin"],
  );
  assert.match(controller.getSnapshot().error!, /invalid/);
  controller.dispose();
});

test("pin receipt retry retains its original revision through filtering and refreshes the selected catalog", async () => {
  const writes: Record<string, unknown>[] = [];
  let unknown = true;
  let pinned = true;
  const controller = makeController(async (request) => {
    if (request.op === "spec.listDrafts") return emptyDrafts;
    if (request.op === "spec.launcher")
      return {
        apps:
          request.pinnedOnly && !pinned
            ? []
            : [app("app", pinned, writes.length ? 9 : 2)],
        nextCursor: null,
      };
    writes.push(request);
    if (unknown) throw new Error("lost response");
    pinned = false;
    return { shortcut: { appId: "app", pinned: false, revision: 3 } };
  });
  await controller.load();
  await controller.setPinned(controller.getSnapshot().apps[0], false);
  assert.equal(controller.getSnapshot().pendingStatus, "uncertain");
  await controller.setPinnedOnly(true);
  assert.equal(writes.length, 1);
  unknown = false;
  await controller.retry();
  assert.deepEqual(writes[1], writes[0]);
  assert.equal(writes[1].expectedRevision, 2);
  assert.equal(controller.getSnapshot().pinnedOnly, true);
  assert.deepEqual(controller.getSnapshot().apps, []);
  assert.equal(controller.getSnapshot().pending, null);
  controller.dispose();
});

test("current access denial clears private catalogs and disposed account ignores late filter responses", async () => {
  const gate = deferred<unknown>();
  let phase = "initial";
  const controller = makeController(async (request) => {
    if (request.op === "spec.listDrafts") return emptyDrafts;
    if (phase === "deny")
      throw new BackendError("No access", "forbidden", "service", false, 403);
    if (phase === "late") return gate.promise;
    return { apps: [app("private_app")], nextCursor: null };
  });
  await controller.load();
  phase = "deny";
  await controller.setPinnedOnly(true);
  assert.deepEqual(controller.getSnapshot().apps, []);
  assert.deepEqual(controller.getSnapshot().drafts, []);
  phase = "late";
  const pending = controller.setPinnedOnly(false);
  controller.dispose();
  gate.resolve({ apps: [app("late_private")], nextCursor: null });
  await pending;
  assert.deepEqual(controller.getSnapshot().apps, []);
});

// Exercise the shipped React Native Web DOM mapping rather than a duplicate props helper.
const webHooks = registerHooks({
  resolve(specifier, context, next) {
    if (specifier === "react-native") return next("react-native-web", context);
    if (
      context.parentURL?.includes("react-native-safe-area-context/") &&
      ["./NativeSafeAreaProvider", "./SafeAreaView"].includes(specifier)
    ) {
      return next(`${specifier}.web.js`, context);
    }
    return next(specifier, context);
  },
});
const web = Promise.all([import("./ui"), import("./FullLauncher")]);
test.after(() => webHooks.deregister());

test("shared Choices and Toggle expose checked and disabled states through the actual RNWeb DOM mapper", async () => {
  const [{ Choices, Toggle }] = await web;
  const html = renderToStaticMarkup(
    createElement(Choices, {
      label: "Mode",
      values: ["live", "preview", "builder"],
      value: "live",
      disabled: true,
      onChange() {},
    }),
  );
  const radios = html.match(/<[^>]+role="radio"[^>]*>/g)!;
  assert.equal(radios.length, 3);
  assert.equal(
    radios.filter((v) => v.includes('aria-checked="true"')).length,
    1,
  );
  assert.equal(
    radios.filter((v) => v.includes('aria-checked="false"')).length,
    2,
  );
  assert.ok(radios.every((v) => v.includes('aria-disabled="true"')));
  for (const checked of [true, false]) {
    const checkbox = renderToStaticMarkup(
      createElement(Toggle, {
        label: "Pins",
        value: checked,
        disabled: true,
        onChange() {},
      }),
    );
    assert.match(checkbox, new RegExp(`aria-checked="${checked}"`));
    assert.match(checkbox, /aria-disabled="true"/);
  }
});

test("returning workbench renders recent apps and private drafts before collapsed creation; empty workspace preserves onboarding", async () => {
  const [, { FullLauncher }] = await web;
  const controller = makeController(async (request) =>
    request.op === "spec.listDrafts"
      ? {
          drafts: [
            {
              engine: "appspec.v1",
              appId: "private_draft",
              workspaceId: "workspace",
              name: "My private draft",
              revision: 2,
              stale: false,
              updatedAt: null,
            },
          ],
          nextCursor: null,
        }
      : { apps: [app("Recent app")], nextCursor: null },
  );
  await controller.load();
  function markup(state: WorkspaceState) {
    const readOnly = {
      ...controller,
      getSnapshot: () => state,
      subscribe: () => () => {},
    } as unknown as FullWorkspaceController;
    return renderToStaticMarkup(
      createElement(FullLauncher, {
        controller: readOnly,
        onOpenApp() {},
        onOpenBoundedApp() {},
      }),
    );
  }
  const returning = markup(controller.getSnapshot());
  assert.ok(
    returning.indexOf("Recent apps you can access") <
      returning.indexOf("Resume your private drafts"),
  );
  assert.ok(
    returning.indexOf("Resume your private drafts") <
      returning.indexOf("Create a new app"),
  );
  assert.match(returning, /New app: jump to creation options/);
  assert.match(returning, /Show creation options/);
  assert.doesNotMatch(returning, /New app name/);
  const empty = markup({ ...controller.getSnapshot(), apps: [], drafts: [] });
  assert.match(empty, /Start something useful/);
  assert.match(empty, /New app name/);
  assert.doesNotMatch(empty, /No private drafts to resume/);
  const pins = markup({
    ...controller.getSnapshot(),
    pinnedOnly: true,
    apps: [],
  });
  assert.match(pins, /No pinned apps in this workspace/);
  assert.match(pins, /My private draft/);
  assert.doesNotMatch(pins, /Start something useful/);
  controller.dispose();
});
