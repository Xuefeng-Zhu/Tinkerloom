import assert from "node:assert/strict";
import test from "node:test";
import { AppwriteBackend, type SdkAdapter } from "./core";
import { BackendError } from "./errors";

function fixture() {
  let body = "{}",
    status = 200;
  const requests: string[] = [];
  const sdk: SdkAdapter = {
    newId: () => "generated",
    account: {
      get: async () => null,
      create: async () => null,
      createEmailPasswordSession: async () => null,
      deleteSession: async () => null,
    },
    execute: async (input) => {
      requests.push(input);
      return {
        status: "completed",
        responseStatusCode: status,
        responseBody: body,
      };
    },
  };
  return {
    backend: new AppwriteBackend(sdk),
    requests,
    respond(value: unknown, code = 200) {
      body = JSON.stringify(value);
      status = code;
    },
  };
}
test("full spec transport supports larger records while retaining bounded response limits", async () => {
  const s = fixture(),
    result = { record: { text: "x".repeat(300_000) } };
  s.respond(result);
  assert.deepEqual(
    await s.backend.executeSpec({
      op: "spec.getRecord",
      appId: "app",
      recordId: "record",
    }),
    result,
  );
  await assert.rejects(
    s.backend.listApps("workspace"),
    (error) =>
      error instanceof BackendError && error.kind === "invalid_response",
  );
});
test("spec reads and writes preserve definite rejection versus unknown outcome classification", async () => {
  const s = fixture();
  for (const op of [
    "spec.query",
    "spec.watch",
    "spec.media.usage",
    "spec.publish",
    "spec.generate",
    "spec.instantiate",
  ]) {
    s.respond({ error: "forbidden" }, 403);
    await assert.rejects(
      s.backend.executeSpec({ op }),
      (error) =>
        error instanceof BackendError &&
        !error.uncertain &&
        error.code === "forbidden",
    );
    s.respond({ error: "backend_unavailable" }, 503);
    await assert.rejects(
      s.backend.executeSpec({ op }),
      (error) =>
        error instanceof BackendError &&
        error.uncertain ===
          !["spec.query", "spec.watch", "spec.media.usage"].includes(op),
    );
  }
});
test("invalid namespaces and executable JSON hooks never reach the SDK", async () => {
  const s = fixture();
  let invoked = 0;
  const hooked = { op: "spec.publish" };
  Object.defineProperty(hooked, "toJSON", {
    value: () => {
      invoked++;
      return {};
    },
  });
  for (const input of [hooked, { op: "admin.worker" }, { op: "createApp" }])
    await assert.rejects(
      s.backend.executeSpec(input),
      (error) => error instanceof BackendError && !error.uncertain,
    );
  assert.equal(invoked, 0);
  assert.equal(s.requests.length, 0);
});
test("mixed app summaries accept only explicit supported engine discriminators", async () => {
  const s = fixture();
  const app = {
    id: "app",
    workspaceId: "workspace",
    name: "Shared app",
    role: "owner",
    archived: false,
    capabilities: {
      editDefinition: true,
      share: true,
      writeRecords: true,
      archive: true,
      revokeAccess: true,
    },
  };
  for (const engine of ["bounded.v1", "appspec.v1"]) {
    s.respond({ apps: [{ ...app, engine }] });
    assert.equal((await s.backend.listApps("workspace"))[0].engine, engine);
  }
  s.respond({ apps: [{ ...app, engine: "model-code" }] });
  await assert.rejects(
    s.backend.listApps("workspace"),
    (error) =>
      error instanceof BackendError && error.kind === "invalid_response",
  );
});
