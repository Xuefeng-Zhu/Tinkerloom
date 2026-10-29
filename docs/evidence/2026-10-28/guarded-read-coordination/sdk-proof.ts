import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { writeFile } from "node:fs/promises";
import { Account, Client, Functions, ExecutionMethod } from "appwrite";
import { AppwriteBackend } from "./apps/mobile/src/backend/core";
import { BackendError } from "./apps/mobile/src/backend/errors";
import { GuardedReadCoordinator } from "./apps/mobile/src/runtime/guardedReads";
import { accountTransport } from "./apps/mobile/src/full/FullRegistry";
const child = spawn("/private/tmp/tinkerloom-dart-3.11.0-arm64/dart-sdk/bin/dart", ["--packages=/Users/frank/mygit/Tinkerloom/appwrite_backend/.dart_tool/package_config.json", "/private/tmp/tinkerloom-guarded-reads/service_bridge.dart"], { stdio: ["pipe", "pipe", "pipe"], env: { ...process.env, DART_SUPPRESS_ANALYTICS: "true" } });
let sequence = 0, readyYes!: (v: any) => void, readyNo!: (e: Error) => void;
const initial = new Promise<any>((yes, no) => { readyYes = yes; readyNo = no; });
const pending = new Map<number, { resolve(v: any): void; reject(e: Error): void }>();
createInterface({ input: child.stdout }).on("line", (line) => { const v = JSON.parse(line); if (v.ready) readyYes(v); else { const p = pending.get(v.id); pending.delete(v.id); if (v.error) p?.reject(new Error(v.error)); else p?.resolve(v.data); } });
child.stderr.on("data", (d) => process.stderr.write(d));
child.on("error", readyNo); child.on("exit", (code) => { if (code) readyNo(new Error(`bridge_exit_${code}`)); });
const rpc = (action: string) => new Promise<any>((resolve, reject) => { const id = ++sequence; pending.set(id, { resolve, reject }); child.stdin.write(JSON.stringify({ id, action }) + "\n"); });
async function main() {
try {
 const fixture = await initial;
 const client = new Client().setEndpoint(fixture.endpoint).setProject("synthetic");
 const functions = new Functions(client);
 const backend = new AppwriteBackend({ account: new Account(client), newId: () => { throw new Error("No IDs from reads"); }, execute: (body) => functions.createExecution({ functionId: "core", body, async: false, method: ExecutionMethod.POST, headers: { "content-type": "application/json" } }) });
 const query = { op: "spec.query", appId: "app-one", versionId: fixture.app.version.id, collectionId: fixture.app.version.spec.collections[0].id, query: {} };
 const app = { op: "spec.getApp", appId: "app-one" };
 await rpc("arm"); const rawFirst = backend.executeSpec(app); const rawFailure = assert.rejects(rawFirst, (e: unknown) => e instanceof BackendError && e.kind === "service" && e.status === 409 && e.code === "transaction_conflict" && !e.uncertain);
 await rpc("paused"); await backend.executeSpec(query); await rpc("release"); await rawFailure;
 const baseline = await rpc("stats"); assert.equal(baseline.failedTransactions, 1);
 const lane = new GuardedReadCoordinator();
 const transport = lane.transport(accountTransport({ execute: (r) => backend.executeSpec(r), expected: { accountId: "alice", epoch: 1, active: true }, readSession: () => ({ accountId: "alice", epoch: 1, active: true }), alive: () => true, onUnauthenticated() {} }));
 const cases = [[app, query], [{ op: "spec.watch", appId: "app-one" }, query], [query, query], [app, { op: "spec.getApp", appId: "app-two" }]];
 const evidence = [];
 for (const pair of cases) {
   const before = await rpc("stats"); await rpc("arm"); const first = transport(pair[0]); await rpc("paused"); const second = transport(pair[1]);
   await new Promise((r) => setTimeout(r, 20)); const held = await rpc("stats"); assert.equal(held.calls.length, before.calls.length + 1);
   await rpc("release"); await Promise.all([first, second]); const after = await rpc("stats");
   assert.equal(after.calls.length, before.calls.length + 2); assert.equal(after.failedTransactions, before.failedTransactions); assert.deepEqual(after.business, before.business);
   evidence.push({ first: pair[0].op, second: pair[1].op, crossApp: pair[0].appId !== pair[1].appId, sdkDispatchWhileFirstHeld: 1, sdkDispatchesTotal: 2, newFailedTransactions: 0, businessUnchanged: true });
 }
 lane.dispose();
 const result = { proof: "actual_appwrite_web_sdk_backend_account_transport_coordinator_service_loopback_rest_optimistic_memory_only", actorAuthentication: "synthetic_injected_alice_not_Cloud_auth", rawOverlap: { confirmedConflict: 1 }, coordinated: evidence, sdkVersion: "29.1.0", business: baseline.business };
 await writeFile("/private/tmp/tinkerloom-guarded-reads/sdk-service-proof.json", JSON.stringify(result, null, 2) + "\n"); console.log(JSON.stringify(result, null, 2));
} finally { await rpc("close"); child.stdin.end(); child.kill("SIGTERM"); }

}
void main().catch((error) => { console.error(error); process.exitCode = 1; child.kill("SIGTERM"); });
