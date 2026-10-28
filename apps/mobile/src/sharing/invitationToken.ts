const alphabet =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/** Exactly 256 random bits, encoded without padding for URLs and invite codes. */
export function encodeInvitationToken(bytes: Uint8Array): string {
  if (!(bytes instanceof Uint8Array) || bytes.length !== 32)
    throw new Error("A secure invitation needs 32 random bytes.");
  let output = "";
  for (let index = 0; index < bytes.length; index += 3) {
    const remaining = bytes.length - index;
    const word =
      (bytes[index] << 16) |
      ((remaining > 1 ? bytes[index + 1] : 0) << 8) |
      (remaining > 2 ? bytes[index + 2] : 0);
    output += alphabet[(word >>> 18) & 63] + alphabet[(word >>> 12) & 63];
    if (remaining > 1) output += alphabet[(word >>> 6) & 63];
    if (remaining > 2) output += alphabet[word & 63];
  }
  return output;
}

export function isInvitationToken(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length === 43 &&
    /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/.test(value)
  );
}
