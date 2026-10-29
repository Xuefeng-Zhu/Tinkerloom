import assert from "node:assert/strict";
import { createRequire, registerHooks } from "node:module";
import test from "node:test";
import { createElement, type ReactNode } from "react";
import { AcceptedConversation } from "./conversation";
import type { Generation } from "./contracts";
const hooks = registerHooks({
  resolve(specifier, context, next) {
    return next(
      specifier === "react-native" ? "react-native-web" : specifier,
      context,
    );
  },
});
const components = Promise.all([
  import("./BuilderWorkspace"),
  import("./ConversationHistory"),
  import("react-native"),
]);
const { renderToStaticMarkup } = createRequire(import.meta.url)(
  "react-dom/server",
) as { renderToStaticMarkup(element: ReactNode): string };
test.after(() => hooks.deregister());
async function render(
  mode: "live" | "build" | "preview",
  width: number,
  fontScale = 1,
) {
  const [{ BuilderWorkspace }, , { Dimensions, Text }] = await components;
  Dimensions.set({ window: { width, height: 720, fontScale, scale: 1 } });
  return renderToStaticMarkup(
    createElement(BuilderWorkspace, {
      mode,
      disabled: false,
      onSelect() {},
      chat: createElement(Text, { nativeID: "chat-sentinel" }, "Private chat"),
      preview: createElement(
        Text,
        { nativeID: "preview-sentinel" },
        "One isolated preview",
      ),
    }),
  );
}
test("phone tabs expose one selected accessible tab and one copy of each stable panel", async () => {
  for (const mode of ["build", "preview"] as const) {
    const html = await render(mode, 390);
    assert.equal((html.match(/id="preview-sentinel"/g) ?? []).length, 1);
    assert.equal((html.match(/id="chat-sentinel"/g) ?? []).length, 1);
    const tags = html.match(/<[^>]+role="tab"[^>]*>/g)!;
    assert.equal(tags.length, 2);
    assert.equal(
      tags.filter((t) => t.includes('aria-selected="true"')).length,
      1,
    );
    assert.ok(
      tags.some(
        (t) =>
          t.includes(
            `aria-label="${mode === "build" ? "Chat and editor" : "Try preview"}"`,
          ) && t.includes('aria-selected="true"'),
      ),
    );
  }
});
test("wide builder presents both panels without duplicating preview, while large text selects tabs", async () => {
  const [{ builderWorkspaceLayout }] = await components;
  assert.deepEqual(builderWorkspaceLayout(849, 1), {
    split: false,
    chatWidth: 330,
  });
  assert.deepEqual(builderWorkspaceLayout(850, 1), {
    split: true,
    chatWidth: 330,
  });
  assert.deepEqual(builderWorkspaceLayout(1280, 1), {
    split: true,
    chatWidth: 380,
  });
  assert.equal(builderWorkspaceLayout(1280, 1.5).split, false);
  assert.equal(builderWorkspaceLayout(NaN, 1).split, false);
  const wide = await render("build", 1280);
  assert.doesNotMatch(wide, /role="tab"/);
  assert.equal((wide.match(/id="preview-sentinel"/g) ?? []).length, 1);
  assert.match(await render("preview", 1280, 2), /role="tablist"/);
  assert.match(await render("live", 390), /aria-hidden="true"/);
});
test("conversation view preserves user text and states factual outcomes without provider output", async () => {
  const [, { ConversationHistory }] = await components;
  const history = new AcceptedConversation();
  const accepted: Generation = {
    id: "job",
    status: "preview ready",
    mode: "create",
    mutation: 1,
    attempts: 1,
    requestText: "  My exact accepted idea\n",
    diagnostics: "Do not echo provider body",
    provider: null,
    model: null,
    nextAttemptAt: "2030-01-01T00:00:00Z",
    failureCategory: null,
  };
  history.accept(accepted, "accepted");
  history.observe(accepted);
  history.accept(
    {
      ...accepted,
      id: "latest",
      status: "stale",
      requestText: "Latest superseded",
    },
    "restored",
  );
  history.observe({
    ...accepted,
    id: "latest",
    status: "stale",
    requestText: "Latest superseded",
  });
  const html = renderToStaticMarkup(
    createElement(ConversationHistory, { conversation: history.getSnapshot() }),
  );
  assert.match(html, /Accepted request/);
  assert.match(html, /Restored latest request/);
  assert.ok(html.includes(accepted.requestText));
  assert.match(html, /Publication is a separate action/);
  assert.match(html, /superseded/);
  assert.doesNotMatch(html, /Do not echo provider body/);
  assert.match(html, /session only/);
});
