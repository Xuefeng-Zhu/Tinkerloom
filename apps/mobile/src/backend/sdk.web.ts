import { Account, Client, ExecutionMethod, Functions } from "appwrite";
import { randomUUID } from "expo-crypto";
import type { PublicConfig } from "./config";
import type { SdkAdapter } from "./core";

export function createSdk(config: PublicConfig): SdkAdapter {
  const client = new Client()
    .setEndpoint(config.endpoint)
    .setProject(config.projectId);
  const account = new Account(client);
  const functions = new Functions(client);
  return {
    account,
    newId: () => randomUUID(),
    execute: (body) =>
      functions.createExecution({
        functionId: config.functionId,
        body,
        async: false,
        method: ExecutionMethod.POST,
        headers: { "content-type": "application/json" },
      }),
  };
}
