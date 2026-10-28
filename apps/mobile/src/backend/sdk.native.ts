import "react-native-url-polyfill/auto";
import {
  Account,
  Client,
  ExecutionMethod,
  Functions,
  ID,
} from "react-native-appwrite";
import type { PublicConfig } from "./config";
import type { SdkAdapter } from "./core";

export function createSdk(config: PublicConfig): SdkAdapter {
  const client = new Client()
    .setEndpoint(config.endpoint)
    .setProject(config.projectId)
    .setPlatform(config.platformId);
  const account = new Account(client);
  const functions = new Functions(client);
  return {
    account,
    newId: () => ID.unique(),
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
