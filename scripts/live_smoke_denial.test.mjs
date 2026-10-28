import assert from "node:assert/strict";
import test from "node:test";
import {
  containsPrivateRowFields,
  isPrivateRowReadDenied,
} from "./live_smoke_denial.mjs";

test("explicit authentication and authorization denials remain accepted", () => {
  for (const status of [401, 403]) {
    assert.equal(
      isPrivateRowReadDenied({ status, data: { type: "user_unauthorized" } }),
      true,
    );
  }
});

test("concealed reads require a proven existing row and the exact Appwrite error", () => {
  const concealed = { status: 404, data: { type: "row_not_found", code: 404 } };
  assert.equal(
    isPrivateRowReadDenied(concealed, { knownExistingRow: true }),
    true,
  );
  assert.equal(isPrivateRowReadDenied(concealed), false);
  assert.equal(
    isPrivateRowReadDenied(concealed, { knownExistingRow: false }),
    false,
  );
  for (const type of [
    "table_not_found",
    "database_not_found",
    "general_route_not_found",
    "not_found",
    undefined,
  ]) {
    assert.equal(
      isPrivateRowReadDenied(
        { status: 404, data: { type } },
        { knownExistingRow: true },
      ),
      false,
    );
  }
});

test("successful and unrelated failed requests cannot pass as a denial", () => {
  for (const status of [200, 201, 400, 409, 429, 500]) {
    assert.equal(
      isPrivateRowReadDenied(
        { status, data: { type: "row_not_found" } },
        { knownExistingRow: true },
      ),
      false,
    );
  }
});

test("private row fields at any depth invalidate every denial status", () => {
  for (const field of ["$id", "ownerId", "name", "rows"]) {
    for (const status of [401, 403, 404]) {
      for (const leak of [
        { [field]: "synthetic" },
        { nested: [{ [field]: "synthetic" }] },
      ]) {
        const data = { type: "row_not_found", ...leak };
        assert.equal(containsPrivateRowFields(data), true);
        assert.equal(
          isPrivateRowReadDenied({ status, data }, { knownExistingRow: true }),
          false,
        );
      }
    }
  }
  assert.equal(
    containsPrivateRowFields({
      type: "row_not_found",
      code: 404,
      message: "Row unavailable",
    }),
    false,
  );
});
