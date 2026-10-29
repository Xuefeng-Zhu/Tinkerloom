/** Offline orchestration test: real Dart business service; auth/Storage HTTP
 * boundaries are explicit stubs. This is not Cloud/private-worker evidence. */
import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { randomBytes } from "node:crypto";
import { runMediaSmoke, readMediaConfiguration } from "./live_media_smoke.mjs";
const args = [
  "--endpoint",
  "https://appwrite.invalid/v1",
  "--project-id",
  "synthetic-project",
  "--function-id",
  "synthetic-core",
  "--bucket-id",
  "synthetic-media",
  "--worker-function-id",
  "synthetic-worker",
  "--source-commit",
  "fc71abc",
  "--source-sha256",
  "a".repeat(64),
  "--worker-source-commit",
  "b542d9f",
  "--worker-source-sha256",
  "b".repeat(64),
  "--core-deployment-id",
  "synthetic-core-deploy",
  "--worker-deployment-id",
  "synthetic-worker-deploy",
];
test(
  "full media orchestration agrees with real backend validators and receipts offline",
  { timeout: 120000 },
  async (t) => {
    const cwd = fileURLToPath(new URL("../appwrite_backend/", import.meta.url));
    const child = spawn(
      process.env.TINKERLOOM_TEST_DART ?? "dart",
      ["--suppress-analytics", "run", "test/media_probe_bridge.dart"],
      { cwd, stdio: ["pipe", "pipe", "pipe"] },
    );
    t.after(() => {
      child.stdin.end();
      child.kill("SIGTERM");
    });
    const lines = createInterface({ input: child.stdout }),
      pending = [];
    let stderrBytes = 0;
    child.stderr.on("data", (chunk) => {
      stderrBytes += chunk.length;
    });
    child.on("error", () => {
      for (const p of pending.splice(0))
        p.reject(new Error("offline_bridge_start_failed"));
    });
    child.on("exit", () => {
      for (const p of pending.splice(0))
        p.reject(new Error("offline_bridge_exited"));
    });
    lines.on("line", (line) => {
      const next = pending.shift();
      if (next) {
        try {
          next.resolve(JSON.parse(line));
        } catch {
          next.reject(new Error("offline_bridge_protocol_failed"));
        }
      }
    });
    const rpc = (actor, input) =>
      new Promise((resolve, reject) => {
        pending.push({ resolve, reject });
        child.stdin.write(JSON.stringify({ actor, input }) + "\n");
      });
    const accounts = new Map(),
      sessions = new Map();
    const response = (status, data, headers = {}) =>
      new Response(data === undefined ? null : JSON.stringify(data), {
        status,
        headers,
      });
    let businessCalls = 0;
    const fakeFetch = async (url, options) => {
      const path = new URL(url).pathname.slice(3),
        body = options.body ? JSON.parse(options.body) : null;
      const cookie = options.headers.Cookie?.split("=", 2)[1],
        actor = sessions.get(cookie);
      if (path === "/account" && options.method === "POST") {
        accounts.set(body.email, body.userId);
        return response(201, { $id: body.userId });
      }
      if (path === "/account/sessions/email") {
        const id = accounts.get(body.email),
          token = randomBytes(24).toString("hex");
        sessions.set(token, id);
        return response(
          201,
          {},
          { "Set-Cookie": `a_session=${token}; Path=/; HttpOnly` },
        );
      }
      if (path === "/account" && options.method === "GET")
        return response(200, { $id: actor });
      if (path === "/account/sessions/current" && options.method === "DELETE") {
        sessions.delete(cookie);
        return response(204, undefined, {
          "Set-Cookie": "a_session=; Max-Age=0; Path=/",
        });
      }
      if (path.startsWith("/storage/") || path.startsWith("/tablesdb/"))
        return response(403, { type: "general_access_forbidden", code: 403 });
      if (path === "/functions/synthetic-worker/executions")
        return response(401, { type: "general_unauthorized_scope", code: 401 });
      assert.equal(path, "/functions/synthetic-core/executions");
      assert.ok(actor);
      businessCalls++;
      const result = await rpc(actor, JSON.parse(body.body));
      return response(201, {
        deploymentId: "synthetic-core-deploy",
        status: "completed",
        responseStatusCode: result.status,
        responseBody: JSON.stringify(result.data),
        responseHeaders: { "cache-control": "private, no-store" },
      });
    };
    const report = await runMediaSmoke(readMediaConfiguration(args, {}), {
      fetchImpl: fakeFetch,
      sleep: async () => {
        throw new Error("unexpected_offline_poll_wait");
      },
    });
    assert.equal(
      report.status,
      "passed",
      JSON.stringify(
        report.checks.filter(
          (c) => c.status === "failed" || c.status === "blocked",
        ),
      ),
    );
    assert.equal(report.summary.failed, 0);
    assert.equal(report.summary.blocked, 0);
    assert.equal(report.summary.pending, 1);
    assert.equal(report.accounts.length, 2);
    assert.equal(report.budget.httpRequests < 300, true);
    assert.equal(businessCalls > 60, true);
    assert.equal(stderrBytes, 0);
    assert.equal(
      report.checks.find(
        (c) => c.name === "revoke_current_access_and_receipt_denial",
      ).status,
      "passed",
    );
    assert.equal(
      report.checks.find(
        (c) => c.name === "builder_own_upload_receipt_current_authority",
      ).status,
      "passed",
    );
  },
);
