/** Optional, memory-only synthetic actor reuse. No I/O occurs on import. */
import { randomBytes } from "node:crypto";
import { types } from "node:util";
import { AppwriteUserClient, HttpBudget } from "./live_full_transport.mjs";
import { FullProbeError } from "./live_full_contract.mjs";
const labels = new Set(["owner", "builder", "member", "viewer", "outsider"]);
export async function readSyntheticCredentials(
  provider,
  label,
  runId,
  privateValues,
) {
  if (typeof provider !== "function" || !labels.has(label))
    throw new FullProbeError("configuration_invalid");
  let value;
  try {
    const supplied = provider(label, Object.freeze({ runId }));
    if (types.isPromise(supplied)) {
      // Providers are trusted authored code; credentials still have a strict
      // data shape. Never read a supplied object's arbitrary then accessor.
      for (const key of ["then", "constructor"]) {
        const own = Object.getOwnPropertyDescriptor(supplied, key);
        if (own && !Object.hasOwn(own, "value"))
          throw new FullProbeError("configuration_invalid");
      }
      value = await Promise.prototype.then.call(supplied, (result) => result);
    } else value = supplied;
  } catch {
    throw new FullProbeError("configuration_invalid");
  }
  if (
    !value ||
    typeof value !== "object" ||
    ![Object.prototype, null].includes(Object.getPrototypeOf(value))
  )
    throw new FullProbeError("configuration_invalid");
  const keys = Reflect.ownKeys(value);
  if (
    keys.length !== 3 ||
    !["id", "email", "password"].every((key) => keys.includes(key))
  )
    throw new FullProbeError("configuration_invalid");
  const copy = {};
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (
      !descriptor ||
      !Object.hasOwn(descriptor, "value") ||
      typeof descriptor.value !== "string"
    )
      throw new FullProbeError("configuration_invalid");
    copy[key] = descriptor.value;
  }
  privateValues.add(copy.email);
  privateValues.add(copy.password);
  if (
    !/^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(copy.id) ||
    copy.email.length > 254 ||
    !/^tinkerloom-[a-z0-9-]+@example\.test$/.test(copy.email) ||
    copy.password.length < 8 ||
    copy.password.length > 128 ||
    /[\r\n]/.test(copy.password)
  )
    throw new FullProbeError("configuration_invalid");
  return Object.freeze(copy);
}
/** One normal client create per label. Unknown results never create a replacement. */
export class EphemeralSyntheticAccounts {
  #pending = new Map();
  #observed = new Map();
  #privateValues = new Set();
  #closed = false;
  #client;
  #budget;
  #runId;
  constructor(configuration, { fetchImpl = globalThis.fetch } = {}) {
    this.#runId =
      "qa-suite-" +
      Date.now().toString(36) +
      "-" +
      randomBytes(4).toString("hex");
    this.#budget = new HttpBudget(5, 0);
    this.#client = new AppwriteUserClient(configuration, {
      budget: this.#budget,
      privateValues: this.#privateValues,
      fetchImpl,
    });
  }
  actorCredentials = async (label) => {
    if (this.#closed || !labels.has(label))
      throw new FullProbeError("configuration_invalid");
    if (!this.#pending.has(label))
      this.#pending.set(label, this.#create(label));
    return this.#pending.get(label);
  };
  async #create(label) {
    const credentials = Object.freeze({
      id: "usr-" + randomBytes(14).toString("hex"),
      email: `tinkerloom-${this.#runId}-${label}@example.test`,
      password: "T!" + randomBytes(24).toString("hex") + "a9",
    });
    this.#privateValues.add(credentials.email);
    this.#privateValues.add(credentials.password);
    const observed = {
      label,
      id: credentials.id,
      creationStatus: "unconfirmed",
    };
    this.#observed.set(label, observed);
    const response = await this.#client.request("POST", "/account", {
      userId: credentials.id,
      email: credentials.email,
      password: credentials.password,
      name: "Synthetic Tinkerloom suite QA " + label,
    });
    observed.httpStatus = response.status;
    if (response.status !== 201 || response.data?.$id !== credentials.id)
      throw new FullProbeError("configuration_invalid");
    observed.creationStatus = "created";
    if (this.#closed) throw new FullProbeError("configuration_invalid");
    return credentials;
  }
  snapshot() {
    return {
      runId: this.#runId,
      maxSyntheticAccounts: 5,
      accountCreateHttpRequests: this.#budget.used,
      accounts: [...this.#observed.values()].map((value) => ({ ...value })),
      credentialsPersisted: false,
      authenticationBypassed: false,
      automaticCreationRetries: 0,
    };
  }
  forget() {
    this.#closed = true;
    this.#pending.clear();
    this.#observed.clear();
    this.#privateValues.clear();
    this.#client.cookies.clear();
  }
}
