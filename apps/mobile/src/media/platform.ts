import type { HostLifetime } from "../host/scope";
import type { MediaPorts } from "./types";
import { fail } from "./codec";
/** Metro selects .web/.native; nonplatform tests must explicitly inject ports. */
export function createPrivateMediaPorts(_lifetime: HostLifetime): MediaPorts {
  return fail("media_platform_unavailable");
}
