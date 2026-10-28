import { AppwriteBackend } from "./core";
import { createSdk } from "./sdk";
import { validatePublicConfig } from "./config";
import type { PublicConfig } from "./config";
import { BackendError } from "./errors";
import type { AppBackend } from "./types";

export { readPublicConfig, validatePublicConfig } from "./config";
export type { PublicConfig } from "./config";
export { BackendError } from "./errors";
export type * from "./types";

export function createBackend(config: PublicConfig): AppBackend {
  const checked = validatePublicConfig(config);
  if (!checked.config) {
    throw new BackendError(
      "Appwrite configuration is invalid.",
      "invalid_configuration",
      "configuration",
    );
  }
  return new AppwriteBackend(createSdk(checked.config));
}
