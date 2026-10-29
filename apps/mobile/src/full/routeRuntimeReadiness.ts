import type { RuntimeManifest } from "../runtime/functionAdapter";
/** Called only while the runtime is absent. Published metadata can be installed
 * before its replacement runtime; it is not an unpublished-link rejection. */
export function waitForRouteRuntime(
  app: Pick<RuntimeManifest, "version"> | null,
): boolean {
  return app === null || app.version !== null;
}
