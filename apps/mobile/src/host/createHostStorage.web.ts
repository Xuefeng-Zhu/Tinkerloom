import { BrowserEncryptedStorage } from "./browserStorage";
import { HostLifetime } from "./scope";
import type { HostScope } from "./scope";
import { hostStores } from "./storage";

export function createHostStorage(scope: HostScope) {
  const lifetime = new HostLifetime(scope);
  return hostStores(lifetime, new BrowserEncryptedStorage(lifetime));
}
