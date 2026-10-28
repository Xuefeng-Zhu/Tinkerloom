import assert from "node:assert/strict";
import test from "node:test";
import { AppwriteBackend, type SdkAdapter } from "./core";
import { BackendError } from "./errors";
import type { CreateInvitation, Invitation, SetGrant } from "./types";

const token = "a".repeat(42) + "A";
const invite: Invitation = {
  id: "invite",
  appId: "app",
  issuerId: "owner",
  role: "builder",
  recipientId: null,
  createdAt: "2026-10-28T10:00:00.123456Z",
  expiresAt: "2026-11-04T10:00:00.123456Z",
  revoked: false,
  acceptedBy: null,
};
const create: CreateInvitation = {
  appId: "app",
  id: "invite",
  operationId: "operation",
  role: "builder",
  recipientId: null,
  token,
};
function scenario() {
  let body: unknown = {};
  let failure: unknown;
  let status = 200;
  const requests: string[] = [];
  const sdk: SdkAdapter = {
    newId: () => "generated",
    account: {
      get: async () => null,
      create: async () => null,
      createEmailPasswordSession: async () => null,
      deleteSession: async () => null,
    },
    execute: async (payload) => {
      requests.push(payload);
      if (failure) throw failure;
      return {
        status: "completed",
        responseStatusCode: status,
        responseBody: JSON.stringify(body),
      };
    },
  };
  return {
    backend: new AppwriteBackend(sdk),
    requests,
    succeed: (value: unknown) => {
      failure = undefined;
      status = 200;
      body = value;
    },
    fail: () => {
      failure = new TypeError("Lost response");
    },
    error: (code: string, http: number) => {
      failure = undefined;
      status = http;
      body = { error: code, message: "private bearer token" };
    },
  };
}
const invalid = (error: unknown) =>
  error instanceof BackendError && error.kind === "invalid_response";
const unknownMutation = (error: unknown) =>
  invalid(error) && (error as BackendError).uncertain;

test("invitation inspection validates the real app, role and expiry without accepting membership", async () => {
  const s = scenario();
  const preview = {
    appId: "app",
    appName: "Shared planner",
    role: "builder",
    expiresAt: invite.expiresAt,
    accepted: false,
  };
  s.succeed({ invitation: preview });
  assert.deepEqual(await s.backend.inspectInvitation(token), preview);
  assert.deepEqual(JSON.parse(s.requests[0]), {
    op: "inspectInvitation",
    token,
  });
  for (const overrides of [
    { role: "owner" },
    { accepted: "false" },
    { appName: " padded " },
    { appId: 12 },
    { expiresAt: "2026-02-30T10:00:00.000Z" },
    { token },
  ]) {
    s.succeed({ invitation: { ...preview, ...overrides } });
    await assert.rejects(s.backend.inspectInvitation(token), invalid);
  }
  assert.equal(
    s.requests.some((body) => JSON.parse(body).op === "acceptInvitation"),
    false,
  );
});

test("invitation creation and acceptance retain exact tokens and operation IDs across unknown responses", async () => {
  const s = scenario();
  const original = JSON.stringify(create);
  s.fail();
  await assert.rejects(
    s.backend.createInvitation(create),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  s.succeed({ invitation: invite });
  assert.deepEqual(await s.backend.createInvitation(create), invite);
  assert.equal(s.requests[0], s.requests[1]);
  assert.equal(JSON.stringify(create), original);
  const accept = { token, operationId: "accept-op" };
  s.fail();
  await assert.rejects(
    s.backend.acceptInvitation(accept),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  s.succeed({ appId: "app" });
  assert.deepEqual(await s.backend.acceptInvitation(accept), { appId: "app" });
  assert.equal(s.requests[2], s.requests[3]);
});

test("malformed invitation receipts cannot confirm a mutation or expose a token", async () => {
  const s = scenario();
  for (const overrides of [
    { id: "other" },
    { appId: "other" },
    { role: "owner" },
    { recipientId: "other" },
    { acceptedBy: "someone" },
    { revoked: true },
    { token },
    { tokenHash: "hash" },
    { createdAt: "2026-02-30T10:00:00.000Z" },
    { createdAt: "2026-10-28T24:00:00.000Z" },
    { expiresAt: "2026-11-04T10:00:00Z" },
    { expiresAt: "2026-11-05T10:00:00.123456Z" },
  ]) {
    s.succeed({ invitation: { ...invite, ...overrides } });
    await assert.rejects(s.backend.createInvitation(create), unknownMutation);
  }
  s.succeed({ appId: "app", token });
  await assert.rejects(
    s.backend.acceptInvitation({ token, operationId: "accept-op" }),
    unknownMutation,
  );
});

test("invalid invitation commands and noncanonical base64 padding bits fail before dispatch", async () => {
  const s = scenario();
  for (const badToken of [
    "a".repeat(42),
    "a".repeat(44),
    "a".repeat(43),
    "a".repeat(42) + "=",
    " " + token,
  ]) {
    await assert.rejects(
      s.backend.createInvitation({ ...create, token: badToken }),
      (error: unknown) =>
        error instanceof BackendError &&
        !error.uncertain &&
        error.status === 400,
    );
    await assert.rejects(
      s.backend.acceptInvitation({ token: badToken, operationId: "accept-op" }),
      (error: unknown) => error instanceof BackendError && !error.uncertain,
    );
  }
  assert.equal(s.requests.length, 0);
});

test("invitation pages validate identity, duplicate rows, metadata and finite page bounds", async () => {
  const s = scenario();
  s.succeed({ invitations: [invite], nextCursor: "opaque-row" });
  assert.deepEqual(await s.backend.listInvitations("app"), {
    invitations: [invite],
    nextCursor: "opaque-row",
  });
  s.succeed({ invitations: [], nextCursor: "filtered-row" });
  assert.equal(
    (await s.backend.listInvitations("app", "previous-row")).nextCursor,
    "filtered-row",
  );
  for (const body of [
    { invitations: [invite, invite], nextCursor: null },
    { invitations: [{ ...invite, appId: "another" }], nextCursor: null },
    { invitations: [{ ...invite, acceptedBy: 17 }], nextCursor: null },
    {
      invitations: Array.from({ length: 26 }, (_, i) => ({
        ...invite,
        id: `invite-${i}`,
      })),
      nextCursor: null,
    },
    { invitations: [], nextCursor: "previous-row" },
  ]) {
    s.succeed(body);
    await assert.rejects(
      s.backend.listInvitations("app", "previous-row"),
      invalid,
    );
  }
});

test("invitation revocation confirms only the requested revoked invitation", async () => {
  const s = scenario();
  const command = {
    appId: "app",
    invitationId: "invite",
    operationId: "revoke",
  };
  s.succeed({ invitation: invite });
  await assert.rejects(s.backend.revokeInvitation(command), unknownMutation);
  s.succeed({ invitation: { ...invite, id: "wrong", revoked: true } });
  await assert.rejects(s.backend.revokeInvitation(command), unknownMutation);
  s.succeed({ invitation: { ...invite, revoked: true } });
  assert.equal((await s.backend.revokeInvitation(command)).revoked, true);
});

test("member pages require one immutable owner first, bounded grant revisions and opaque filtered cursors", async () => {
  const s = scenario();
  const owner = { actorId: "owner", role: "owner", revision: 0 };
  const builder = { actorId: "builder", role: "builder", revision: 3 };
  s.succeed({ members: [owner, builder], nextCursor: "grant-row" });
  assert.deepEqual((await s.backend.listMembers("app")).members, [
    owner,
    builder,
  ]);
  s.succeed({ members: [], nextCursor: "filtered-grant-row" });
  assert.deepEqual(await s.backend.listMembers("app", "grant-row"), {
    members: [],
    nextCursor: "filtered-grant-row",
  });
  for (const members of [
    [],
    [builder],
    [{ ...owner, revision: 1 }],
    [owner, { ...builder, role: "owner" }],
    [owner, { ...builder, role: null }],
    [owner, { ...builder, revision: 0 }],
    [owner, { ...builder, revision: 2_147_483_647 }],
    [owner, builder, builder],
  ]) {
    s.succeed({ members, nextCursor: null });
    await assert.rejects(s.backend.listMembers("app"), invalid);
  }
  s.succeed({ members: [owner], nextCursor: null });
  await assert.rejects(s.backend.listMembers("app", "grant-row"), invalid);
});

test("grant changes and revocations require exact actor, role and incremented receipt revision", async () => {
  const s = scenario();
  const command: SetGrant = {
    appId: "app",
    actorId: "builder",
    role: "viewer",
    expectedRevision: 3,
    operationId: "grant-change",
  };
  for (const member of [
    { actorId: "wrong", role: "viewer", revision: 4 },
    { actorId: "builder", role: "builder", revision: 4 },
    { actorId: "builder", role: "viewer", revision: 3 },
  ]) {
    s.succeed({ member });
    await assert.rejects(s.backend.setGrant(command), unknownMutation);
  }
  s.error("transaction_conflict", 409);
  await assert.rejects(
    s.backend.setGrant(command),
    (error: unknown) => error instanceof BackendError && error.uncertain,
  );
  s.succeed({ member: { actorId: "builder", role: "viewer", revision: 4 } });
  assert.equal((await s.backend.setGrant(command)).revision, 4);
  assert.equal(s.requests[3], s.requests[4]);
  s.succeed({ member: { actorId: "builder", role: null, revision: 5 } });
  assert.equal(
    (
      await s.backend.setGrant({
        ...command,
        role: null,
        expectedRevision: 4,
        operationId: "revoke-grant",
      })
    ).role,
    null,
  );
});

test("collaboration errors preserve safe codes without echoing server-supplied private details", async () => {
  const s = scenario();
  for (const [code, status] of [
    ["invitation_unavailable", 404],
    ["app_archived", 403],
    ["forbidden", 403],
    ["operation_conflict", 409],
    ["quota_exceeded", 429],
  ] as const) {
    s.error(code, status);
    await assert.rejects(
      s.backend.createInvitation(create),
      (error: unknown) =>
        error instanceof BackendError &&
        error.code === code &&
        error.status === status &&
        !error.uncertain &&
        !error.message.includes("private"),
    );
  }
});
