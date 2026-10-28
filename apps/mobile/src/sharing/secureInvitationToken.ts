import { getRandomBytesAsync } from "expo-crypto";
import { encodeInvitationToken } from "./invitationToken";

/** The asynchronous native API has no development Math.random fallback. */
export async function createInvitationToken(): Promise<string> {
  try {
    return encodeInvitationToken(await getRandomBytesAsync(32));
  } catch {
    throw new Error("A secure invitation could not be created. Try again.");
  }
}
