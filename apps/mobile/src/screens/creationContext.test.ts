import assert from "node:assert/strict";
import test from "node:test";
import { creationWorkspace } from "./creationContext";

const workspaces = [
  { id: "alpha", name: "Everyday" },
  { id: "beta", name: "Projects" },
];

test("a retained app request names the original workspace after selection changes", () => {
  assert.deepEqual(
    creationWorkspace(
      {
        kind: "app",
        command: { id: "request", name: "Planner", workspaceId: "alpha" },
      },
      "beta",
      workspaces,
    ),
    { id: "alpha", name: "Everyday" },
  );
});

test("a missing original workspace keeps its ID and never falls back to the current selection", () => {
  assert.deepEqual(
    creationWorkspace(
      {
        kind: "app",
        command: { id: "request", name: "Planner", workspaceId: "unlisted" },
      },
      "beta",
      workspaces,
    ),
    { id: "unlisted", name: undefined },
  );
  assert.deepEqual(
    creationWorkspace(
      { kind: "app", command: { id: "request", name: "Planner" } },
      "beta",
      workspaces,
    ),
    { id: null, name: undefined },
  );
});

test("a fresh app request uses the selected workspace while workspace creation has no parent", () => {
  assert.deepEqual(
    creationWorkspace({ kind: "app", command: null }, "beta", workspaces),
    {
      id: "beta",
      name: "Projects",
    },
  );
  assert.equal(
    creationWorkspace({ kind: "workspace", command: null }, "beta", workspaces),
    null,
  );
  assert.equal(creationWorkspace(null, "beta", workspaces), null);
});
