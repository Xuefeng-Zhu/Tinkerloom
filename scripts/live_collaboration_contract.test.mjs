import assert from "node:assert/strict";
import test from "node:test";
import {
  safeObservation,
  validDocument,
  validInvitation,
  validPreview,
  validRecordPage,
} from "./live_collaboration_contract.mjs";

const doc = {
  id: "app",
  workspaceId: "workspace",
  name: "Planner",
  role: "builder",
  archived: false,
  capabilities: {
    editDefinition: true,
    share: true,
    writeRecords: true,
    archive: false,
    revokeAccess: true,
  },
  draftRevision: 1,
  candidateRevision: 7,
  basePublishedRevision: 3,
  publishedRevision: 5,
  definition: { title: "My private draft" },
  publishedDefinition: { title: "Published" },
};

test("new DTO checks distinguish local/global draft counters and reject privileges or private fields on reader responses", () => {
  assert.equal(validDocument(doc), true);
  for (const change of [
    { candidateRevision: undefined },
    { token: "secret" },
    { ownerId: "owner" },
    { capabilities: { ...doc.capabilities, archive: true } },
    { role: "viewer" },
    { candidateRevision: 0 },
    { basePublishedRevision: 6 },
    { draftRevision: 2_147_483_647 },
  ])
    assert.equal(validDocument({ ...doc, ...change }), false);
});

test("invitation DTO checks reject secret echoes and invalid civil timestamps", () => {
  const invitation = {
    id: "invite",
    appId: "app",
    issuerId: "owner",
    role: "builder",
    recipientId: "recipient",
    createdAt: "2026-10-28T10:00:00.123456Z",
    expiresAt: "2026-11-04T10:00:00.123456Z",
    revoked: false,
    acceptedBy: null,
  };
  assert.equal(validInvitation(invitation, "app"), true);
  for (const change of [
    { tokenHash: "secret" },
    { token: "secret" },
    { role: "owner" },
    { acceptedBy: "someone-else" },
    { createdAt: "2026-02-30T10:00:00.123456Z" },
    { expiresAt: "2026-11-04T24:00:00.123456Z" },
    { expiresAt: "2026-11-05T10:00:00.123456Z" },
  ])
    assert.equal(validInvitation({ ...invitation, ...change }, "app"), false);
  const preview = {
    appId: "app",
    appName: "Planner",
    role: "builder",
    expiresAt: invitation.expiresAt,
    accepted: false,
  };
  assert.equal(validPreview(preview), true);
  assert.equal(validPreview({ ...preview, token: "secret" }), false);
  const stored = {
    ...invitation,
    createdAt: "2026-10-28T21:05:10.050+00:00",
    expiresAt: "2026-11-04T21:05:10.050+00:00",
  };
  assert.equal(validInvitation(stored, "app"), true);
  assert.equal(validPreview({ ...preview, expiresAt: stored.expiresAt }), true);
  for (const expiresAt of [
    "2026-11-04T21:05:10.050+01:00",
    "2026-02-30T21:05:10.050+00:00",
    "2026-11-04T24:05:10.050+00:00",
  ])
    assert.equal(validPreview({ ...preview, expiresAt }), false);
});

test("report observations use fixed enums and cannot echo raw server strings or bearer-like codes", () => {
  const secret = "a".repeat(42) + "A";
  const sanitized = safeObservation({
    httpStatus: 403,
    functionStatus: 404,
    executionStatus: secret,
    code: secret,
    token: secret,
    password: secret,
    appId: secret,
    message: secret,
    role: secret,
    revision: NaN,
    winnerCount: 1,
  });
  assert.deepEqual(sanitized, {
    httpStatus: 403,
    functionStatus: 404,
    winnerCount: 1,
    observedCode: "unrecognized_error",
  });
  assert.equal(JSON.stringify(sanitized).includes(secret), false);
  assert.equal(
    safeObservation({ code: "invitation_unavailable" }).observedCode,
    "invitation_unavailable",
  );
});

test("record pages reject duplicate identities, private columns and nonfinite values", () => {
  const record = {
    id: "record",
    revision: 1,
    values: { title: "Synthetic", amount: 0, done: false },
  };
  const page = { records: [record], definitionRevision: 3, nextCursor: null };
  assert.equal(validRecordPage(page), true);
  assert.equal(validRecordPage({ ...page, records: [record, record] }), false);
  assert.equal(
    validRecordPage({ ...page, records: [{ ...record, ownerId: "owner" }] }),
    false,
  );
  assert.equal(
    validRecordPage({
      ...page,
      records: [{ ...record, values: { amount: Infinity } }],
    }),
    false,
  );
});
