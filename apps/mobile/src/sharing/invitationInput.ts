import { isInvitationToken } from "./invitationToken";

const invitationPath = /^\/invite\/([A-Za-z0-9_-]{43})\/?$/;
const developmentPath = /^\/--\/invite\/([A-Za-z0-9_-]{43})\/?$/;

/** Extract only a canonical code. Pasted URLs are never opened or fetched. */
export function readInvitationToken(input: string): string | null {
  const value = input.trim();
  if (value.length === 43) return isInvitationToken(value) ? value : null;
  if (!value || value.length > 2048 || /[\s\\]/.test(value)) return null;
  try {
    const url = new URL(value);
    if (url.username || url.password || url.search || url.hash) return null;
    let candidate: string | undefined;
    if (url.protocol === "http:" || url.protocol === "https:") {
      if (!url.hostname) return null;
      candidate = invitationPath.exec(url.pathname)?.[1];
    } else if (url.protocol === "exp:" || url.protocol === "exps:") {
      if (!url.hostname) return null;
      candidate = developmentPath.exec(url.pathname)?.[1];
    } else if (url.protocol === "tinkerloom:") {
      if (url.port) return null;
      if (url.hostname === "invite")
        candidate = /^\/([A-Za-z0-9_-]{43})\/?$/.exec(url.pathname)?.[1];
      else if (!url.hostname)
        candidate = invitationPath.exec(url.pathname)?.[1];
    }
    return isInvitationToken(candidate) ? candidate : null;
  } catch {
    return null;
  }
}
