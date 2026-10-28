import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import test from "node:test";
import { encodeInvitationToken, isInvitationToken } from "./invitationToken";

test("invitation encoding preserves all 256 bits in canonical URL-safe text", () => {
  for (const bytes of [
    new Uint8Array(32),
    new Uint8Array(32).fill(255),
    Uint8Array.from({ length: 32 }, (_, index) => index),
    new Uint8Array(randomBytes(32)),
  ]) {
    const token = encodeInvitationToken(bytes);
    assert.equal(token, Buffer.from(bytes).toString("base64url"));
    assert.equal(isInvitationToken(token), true);
    assert.deepEqual(new Uint8Array(Buffer.from(token, "base64url")), bytes);
  }
});

test("invitation codes reject truncated, padded, noncanonical or unsafe tokens", () => {
  const token = encodeInvitationToken(new Uint8Array(32));
  for (const value of [
    null,
    token.slice(1),
    token + "=",
    token.slice(0, -1) + "B",
    " " + token,
    token + "\n",
    token.replace("A", "/"),
  ])
    assert.equal(isInvitationToken(value), false);
  assert.throws(() => encodeInvitationToken(new Uint8Array(31)));
});
