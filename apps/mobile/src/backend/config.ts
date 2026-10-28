export interface PublicConfig {
  endpoint: string;
  projectId: string;
  functionId: string;
  platformId: string;
}

export interface PublicEnvironment {
  endpoint?: string;
  projectId?: string;
  functionId?: string;
  platformId?: string;
}

export function validatePublicConfig(environment: PublicEnvironment): {
  config: PublicConfig | null;
  issues: string[];
} {
  const endpoint = environment.endpoint?.trim().replace(/\/$/, "") ?? "";
  const projectId = environment.projectId?.trim() ?? "";
  const functionId = environment.functionId?.trim() ?? "";
  const platformId = environment.platformId?.trim() || "com.tinkerloom.app";
  const issues: string[] = [];
  if (!endpoint) {
    issues.push("EXPO_PUBLIC_APPWRITE_ENDPOINT is required.");
  } else {
    try {
      const url = new URL(endpoint);
      const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
      if (
        (url.protocol !== "https:" && !(url.protocol === "http:" && local)) ||
        url.username ||
        url.password ||
        url.search ||
        url.hash ||
        url.pathname !== "/v1"
      ) {
        issues.push(
          "Use an HTTPS Appwrite endpoint ending in /v1 (HTTP is allowed for localhost).",
        );
      }
    } catch {
      issues.push(
        "EXPO_PUBLIC_APPWRITE_ENDPOINT must be a valid Appwrite URL.",
      );
    }
  }
  const validId = /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/;
  if (!validId.test(projectId))
    issues.push(
      "EXPO_PUBLIC_APPWRITE_PROJECT_ID is required and must be a valid Appwrite ID.",
    );
  if (!validId.test(functionId))
    issues.push(
      "EXPO_PUBLIC_APPWRITE_FUNCTION_ID is required and must be a valid Appwrite ID.",
    );
  if (!/^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$/.test(platformId)) {
    issues.push(
      "EXPO_PUBLIC_APPWRITE_PLATFORM_ID must match your native bundle/package identifier.",
    );
  }
  return {
    config: issues.length
      ? null
      : { endpoint, projectId, functionId, platformId },
    issues,
  };
}

export function readPublicConfig() {
  // Expo statically replaces these direct property accesses at bundle time.
  return validatePublicConfig({
    endpoint: process.env.EXPO_PUBLIC_APPWRITE_ENDPOINT,
    projectId: process.env.EXPO_PUBLIC_APPWRITE_PROJECT_ID,
    functionId: process.env.EXPO_PUBLIC_APPWRITE_FUNCTION_ID,
    platformId: process.env.EXPO_PUBLIC_APPWRITE_PLATFORM_ID,
  });
}
