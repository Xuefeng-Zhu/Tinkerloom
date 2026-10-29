import assert from "node:assert/strict";
import { createRequire, registerHooks } from "node:module";
import test from "node:test";
import { createElement, type ReactNode } from "react";
import { fullTemplates } from "../full/catalog";
import { decodeAppSpec } from "../spec/decode";
import type { PageSpec, ViewSpecOf } from "../spec/types";
import { RuntimeController } from "../runtime/controller";
import { PreviewRuntimeAdapter } from "../runtime/preview";
import { pageRows, resolveAppearance } from "./appearance";
import {
  compactRecordTable,
  nextContainerWidth,
  useContainerWidth,
} from "./containerWidth";

const planner = fullTemplates.find((t) => t.id === "planner")!.spec;
function todayPage(): PageSpec {
  const original = planner.navigation!.pages.find((p) => p.id === "todayPage")!;
  assert.ok(original, "The actual supported Planner Today page is required");
  return { ...original, layout: "twoColumn" };
}
test("a supported two-column Planner page stacks in its measured split content, independent of the wider window", () => {
  const page = todayPage(),
    views = page.viewIds.map((id) => planner.views.find((v) => v.id === id)!);
  const measuredContent = nextContainerWidth(0, 868);
  assert.deepEqual(
    pageRows(page, views, measuredContent, 1).map((row) =>
      row.map((v) => v.id),
    ),
    views.map((view) => [view.id]),
  );
  assert.ok(
    pageRows(page, views, Math.min(1280, 1200) - 32, 1).some(
      (row) => row.length === 2,
    ),
    "The previous global-window calculation reproduces the wrong pairing",
  );
  const wide = nextContainerWidth(measuredContent, 1000);
  assert.ok(pageRows(page, views, wide, 1).some((row) => row.length === 2));
  assert.ok(pageRows(page, views, wide, 1.5).every((row) => row.length === 1));
  assert.deepEqual(
    pageRows(page, views, 0, 1)
      .flat()
      .map((v) => v.id),
    views.map((v) => v.id),
  );
});
test("a table uses its own measured body width including parent padding, with large-text fallback", () => {
  let width = nextContainerWidth(0, 520);
  assert.equal(compactRecordTable(width, 1), true);
  assert.equal(
    compactRecordTable(850, 1),
    false,
    "A global window lookup would incorrectly use desktop table mode",
  );
  width = nextContainerWidth(width, 639.75);
  assert.equal(compactRecordTable(width, 1), true);
  width = nextContainerWidth(width, 640);
  assert.equal(compactRecordTable(width, 1), false);
  assert.equal(compactRecordTable(width, 1.5), true);
  width = nextContainerWidth(width, 0);
  assert.equal(compactRecordTable(width, 1), true);
  width = nextContainerWidth(width, 868);
  assert.equal(compactRecordTable(width, 1), false);
  for (const malformed of [NaN, Infinity, -1])
    assert.equal(nextContainerWidth(width, malformed), 868);
  assert.equal(compactRecordTable(NaN, 1), true);
});
const hooks = registerHooks({
  resolve(specifier, context, next) {
    return next(
      specifier === "react-native" ? "react-native-web" : specifier,
      context,
    );
  },
});
const components = Promise.all([
  import("./context"),
  import("./views"),
  import("react-native"),
]);
const { renderToStaticMarkup } = createRequire(import.meta.url)(
  "react-dom/server",
) as { renderToStaticMarkup(element: ReactNode): string };
test.after(() => hooks.deregister());
test("the actual record-table component cannot infer a wide layout from the global window before its own layout event", async () => {
  const [{ RendererContext }, { SemanticView }, { Dimensions }] =
    await components;
  Dimensions.set({
    window: { width: 1280, height: 720, fontScale: 1, scale: 1 },
  });
  const spec = decodeAppSpec(
    fullTemplates.find((t) => t.id === "projectHub")!.spec,
  );
  const view = spec.views.find(
    (v) => v.type === "table",
  ) as ViewSpecOf<"table">;
  const adapter = new PreviewRuntimeAdapter(spec),
    controller = new RuntimeController(adapter, () => "operation");
  await controller.refresh();
  const context = {
    controller,
    state: controller.getSnapshot(),
    theme: resolveAppearance(spec),
    navigate() {},
    openRecord() {},
    edit() {},
  };
  const html = renderToStaticMarkup(
    createElement(
      RendererContext.Provider,
      { value: context },
      createElement(SemanticView, { view }),
    ),
  );
  assert.match(html, /Sort the complete matching collection/);
  assert.doesNotMatch(html, /aria-label="Sort by /);
  controller.dispose();
  adapter.dispose();
});

test("the native layout callback carries measured region width into page and table decisions", async () => {
  const [, , { Text }] = await components;
  function MeasuredDecision({ measured }: { measured: number }) {
    const [width, onLayout] = useContainerWidth();
    if (width !== measured)
      onLayout({
        nativeEvent: { layout: { width: measured, height: 100, x: 0, y: 0 } },
      } as import("react-native").LayoutChangeEvent);
    const page = todayPage(),
      views = page.viewIds.map((id) => planner.views.find((v) => v.id === id)!);
    return createElement(
      Text,
      null,
      JSON.stringify({
        width,
        paired: pageRows(page, views, width, 1).some((row) => row.length === 2),
        compact: compactRecordTable(width, 1),
      }),
    );
  }
  for (const [measured, paired, compact] of [
    [868, false, false],
    [1000, true, false],
    [520, false, true],
  ] as const) {
    const html = renderToStaticMarkup(
      createElement(MeasuredDecision, { measured }),
    );
    assert.ok(
      html.includes(
        `&quot;width&quot;:${measured},&quot;paired&quot;:${paired},&quot;compact&quot;:${compact}`,
      ),
    );
  }
});
