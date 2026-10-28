import assert from "node:assert/strict";
import test from "node:test";
import { readInvitationToken } from "./invitationInput";

const token = "AbC" + "d".repeat(39) + "A";

test("manual entry accepts canonical codes and the web, app and Expo invitation URL shapes", () => {
  for (const input of [
    token,
    `  ${token}\n`,
    `https://tinkerloom.example/invite/${token}`,
    `http://127.0.0.1:8426/invite/${token}/`,
    `tinkerloom://invite/${token}`,
    `tinkerloom:///invite/${token}`,
    `exp://192.0.2.1:8081/--/invite/${token}`,
    `exps://development.example/--/invite/${token}`,
  ]) {
    assert.equal(readInvitationToken(input), token, input);
  }
});

test("manual entry rejects noncanonical codes, ambiguous URLs and unrelated destinations", () => {
  for (const input of [
    "",
    token.slice(1),
    `${token}=`,
    "a".repeat(43),
    `${token.slice(0, 20)} ${token.slice(20)}`,
    `https://example.test/other/${token}`,
    `https://example.test/invite/${token}/extra`,
    `https://example.test/invite/${token}?accept=true`,
    `https://example.test/invite/${token}#details`,
    `https://recipient:password@example.test/invite/${token}`,
    `https://example.test/invite/%41${token.slice(1)}`,
    `https://example.test\\invite\\${token}`,
    `tinkerloom://other/invite/${token}`,
    `exp://192.0.2.1:8081/invite/${token}`,
    `file:///invite/${token}`,
    `javascript:open('/invite/${token}')`,
    `/invite/${token}`,
    `https://${"x".repeat(2050)}.example/invite/${token}`,
  ]) {
    assert.equal(readInvitationToken(input), null, input);
  }
});
