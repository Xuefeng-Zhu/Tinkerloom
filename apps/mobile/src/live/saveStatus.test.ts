import assert from "node:assert/strict";
import test from "node:test";
import { savePresentation } from "./saveStatus";

test("ordinary in-flight requests show progress without claiming an ambiguous outcome", () => {
  const expected = {
    draft: "Saving draft…",
    publish: "Publishing…",
    record: "Saving record…",
  } as const;
  for (const kind of ["draft", "publish", "record"] as const) {
    const presentation = savePresentation(kind, true)!;
    assert.equal(presentation.title, expected[kind]);
    assert.equal(presentation.canRetry, false);
    assert.doesNotMatch(
      `${presentation.title} ${presentation.description}`,
      /unconfirmed|retry/i,
    );
  }
});

test("recovery messaging appears only when a retained command is no longer in flight", () => {
  for (const kind of ["draft", "publish", "record"] as const) {
    const presentation = savePresentation(kind, false)!;
    assert.match(presentation.title, /unconfirmed/);
    assert.match(presentation.description, /original input and version/);
    assert.equal(presentation.canRetry, true);
  }
  assert.equal(savePresentation(null, false), null);
  assert.equal(savePresentation(null, true), null);
});
