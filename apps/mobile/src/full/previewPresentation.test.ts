import assert from "node:assert/strict";
import test from "node:test";
import { fullTemplates } from "./catalog";
import { applySemanticEdit } from "./semanticEdits";
import { createIsolatedPreview } from "../runtime/createPreview";
import { PreviewRuntimeAdapter } from "../runtime/preview";

test("presentation updates preserve isolated record data, IDs, command receipts, cursor and controller navigation", async () => {
  const spec = fullTemplates.find((t) => t.id === "planner")!.spec,
    session = createIsolatedPreview(spec),
    adapter = session.controller.adapter as PreviewRuntimeAdapter,
    collection = spec.collections[0];
  const first = await adapter.query(collection.id, { limit: 1 });
  assert.ok(first.nextCursor);
  const create = spec.actions.find(
    (a) => a.capability === "records.create.v1",
  )!;
  const values = Object.fromEntries(
    collection.fields
      .filter((f) => f.required)
      .map((f) => [
        f.id,
        f.type === "choice" ? f.choices![0] : "My private sample",
      ]),
  );
  const input = { data: values };
  const command = {
    appId: adapter.appId,
    versionId: adapter.versionId,
    operationId: "presentation_operation",
    actionId: create.id,
    input,
  };
  const outcome = await adapter.execute(command),
    location = { pageId: spec.navigation!.pages.at(-1)!.id };
  session.controller.navigate(location, true);
  const before = await adapter.get(outcome.recordId!),
    next = applySemanticEdit(
      spec,
      {
        type: "SetAppearance",
        appearance: { style: "editorial", density: "spacious" },
      },
      () => "unused",
    );
  adapter.applyPresentationSpec(next);
  assert.deepEqual(await adapter.get(before.id), before);
  assert.deepEqual(await adapter.execute(command), outcome);
  assert.deepEqual(session.controller.getSnapshot().location, location);
  assert.ok(
    (
      await adapter.query(collection.id, {
        limit: 1,
        cursor: first.nextCursor!,
      })
    ).records.length > 0,
  );
  assert.equal(adapter.spec.appearance?.style, "editorial");
  session.dispose();
});
test("structural preview changes require an explicit new isolated factory session; every template supports no-op strict update", () => {
  for (const template of fullTemplates) {
    const session = createIsolatedPreview(template.spec),
      adapter = session.controller.adapter as PreviewRuntimeAdapter;
    adapter.applyPresentationSpec(structuredClone(template.spec));
    if (template.spec.collections.length) {
      const next = structuredClone(template.spec);
      next.collections[0].fields[0].required =
        !next.collections[0].fields[0].required;
      assert.throws(() => adapter.applyPresentationSpec(next));
    }
    session.dispose();
  }
});
test("visual design uses actual isolated semantic views but record execution remains blocked", async () => {
  const { createDesignPreview } = await import("./createDesignPreview");
  const spec = fullTemplates.find((t) => t.id === "planner")!.spec,
    session = createDesignPreview(spec),
    action = spec.actions.find((a) => a.capability === "records.create.v1")!;
  assert.equal(session.controller.adapter.permits(action), false);
  await assert.rejects(
    session.controller.adapter.execute({
      appId: "preview",
      versionId: "preview_v1",
      operationId: "blocked_design",
      actionId: action.id,
      input: { data: { title: "Must not write", status: "Open" } },
    }),
    /Try preview/,
  );
  const before = await session.controller.adapter.query(
    spec.collections[0].id,
    {},
  );
  assert.equal(
    before.records.some((record) => record.data.title === "Must not write"),
    false,
  );
  session.dispose();
});
