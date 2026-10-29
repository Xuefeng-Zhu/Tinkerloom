/** User-cookie REST transport. Importing never performs a request. No admin headers. */
import { FullProbeError, object, safeFullCode } from "./live_full_contract.mjs";
export class HttpBudget {
  constructor(max = 600, reserve = 9) {
    if (!Number.isInteger(max) || max < 1 || max > 600)
      throw new FullProbeError("configuration_invalid");
    this.max = max;
    this.reserve = reserve;
    this.used = 0;
    this.inFlight = 0;
    this.peak = 0;
    this.trialPeak = 0;
    this.trial = false;
  }
  start(cleanup = false) {
    if (this.used >= this.max - (cleanup ? 0 : this.reserve))
      throw new FullProbeError("http_budget_exhausted");
    this.used++;
    this.inFlight++;
    this.peak = Math.max(this.peak, this.inFlight);
    if (this.trial) this.trialPeak = Math.max(this.trialPeak, this.inFlight);
  }
  finish() {
    this.inFlight--;
  }
  beginTrial() {
    this.trial = true;
    this.trialPeak = 0;
  }
  endTrial() {
    this.trial = false;
    return this.trialPeak;
  }
}
async function boundedText(response, limit) {
  try {
    if (!response.body) return "";
    const reader = response.body.getReader(),
      chunks = [];
    let length = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > limit) {
        await reader.cancel().catch(() => {});
        throw new FullProbeError("response_too_large", {
          httpStatus: response.status,
        });
      }
      chunks.push(value);
    }
    const joined = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      joined.set(chunk, offset);
      offset += chunk.byteLength;
    }
    try {
      return new TextDecoder("utf-8", { fatal: true }).decode(joined);
    } catch {
      throw new FullProbeError("response_not_utf8", {
        httpStatus: response.status,
      });
    }
  } catch (error) {
    if (error instanceof FullProbeError) throw error;
    throw new FullProbeError("response_transport_failure", {
      httpStatus: response.status,
    });
  }
}
export class AppwriteUserClient {
  constructor(
    configuration,
    { budget, privateValues = new Set(), fetchImpl = globalThis.fetch } = {},
  ) {
    this.configuration = configuration;
    this.budget = budget ?? new HttpBudget();
    this.privateValues = privateValues;
    this.fetchImpl = fetchImpl;
    this.cookies = new Map();
    this.deploymentMatches = 0;
  }
  async request(method, path, body, { cleanup = false } = {}) {
    const encoded = body === undefined ? undefined : JSON.stringify(body);
    if (encoded !== undefined && Buffer.byteLength(encoded) > 16 * 1024 * 1024)
      throw new FullProbeError("request_too_large");
    this.budget.start(cleanup);
    try {
      const headers = {
        "X-Appwrite-Project": this.configuration.projectId,
        Origin: this.configuration.origin,
      };
      if (encoded !== undefined) headers["Content-Type"] = "application/json";
      if (this.cookies.size)
        headers.Cookie = [...this.cookies]
          .map(([k, v]) => `${k}=${v}`)
          .join("; ");
      let response;
      try {
        response = await this.fetchImpl(this.configuration.endpoint + path, {
          method,
          headers,
          ...(encoded === undefined ? {} : { body: encoded }),
          redirect: "error",
          signal: AbortSignal.timeout(this.configuration.timeoutMs ?? 45000),
        });
      } catch {
        throw new FullProbeError("request_transport_failure");
      }
      if (typeof response.headers.getSetCookie !== "function")
        throw new FullProbeError("node_cookie_api_unavailable");
      for (const header of response.headers.getSetCookie()) {
        const pair = header.split(";", 1)[0],
          index = pair.indexOf("=");
        if (index < 1) throw new FullProbeError("invalid_session_cookie");
        const name = pair.slice(0, index),
          value = pair.slice(index + 1);
        if (
          !/^[A-Za-z0-9_.-]+$/.test(name) ||
          /[\r\n]/.test(value) ||
          value.length > 16384
        )
          throw new FullProbeError("invalid_session_cookie");
        if (!value || /max-age=0(?:;|$)/i.test(header))
          this.cookies.delete(name);
        else {
          this.cookies.set(name, value);
          this.privateValues.add(value);
        }
      }
      const text = await boundedText(response, 20 * 1024 * 1024);
      let data = null;
      if (text) {
        try {
          data = JSON.parse(text);
        } catch {
          throw new FullProbeError("response_not_json", {
            httpStatus: response.status,
          });
        }
      }
      return {
        status: response.status,
        data,
        retryAfter: response.headers.get("retry-after"),
        rateLimitReset: response.headers.get("x-ratelimit-reset"),
      };
    } finally {
      this.budget.finish();
    }
  }
  async execute(payload) {
    const body = JSON.stringify(payload);
    if (Buffer.byteLength(body) > 6 * 1024 * 1024)
      throw new FullProbeError("request_too_large");
    const outer = await this.request(
      "POST",
      `/functions/${encodeURIComponent(this.configuration.functionId)}/executions`,
      {
        body,
        async: false,
        path: "/",
        method: "POST",
        headers: { "content-type": "application/json" },
      },
    );
    if (outer.status < 200 || outer.status >= 300) return { outer };
    const execution = outer.data;
    if (
      !object(execution) ||
      typeof execution.responseBody !== "string" ||
      Buffer.byteLength(execution.responseBody) > 8 * 1024 * 1024
    )
      throw new FullProbeError("execution_response_invalid");
    let data;
    try {
      data = JSON.parse(execution.responseBody);
    } catch {
      throw new FullProbeError("function_response_not_json", {
        httpStatus: outer.status,
      });
    }
    if (!object(data)) throw new FullProbeError("execution_response_invalid");
    const deploymentMatched =
      execution.deploymentId === this.configuration.coreDeploymentId;
    if (deploymentMatched) this.deploymentMatches++;
    return {
      outer,
      status: execution.responseStatusCode,
      executionStatus: execution.status,
      deploymentMatched,
      data,
    };
  }
}
export const functionObservation = (result) => ({
  httpStatus: result.outer?.status,
  functionStatus: result.status,
  executionStatus: [
    "completed",
    "failed",
    "processing",
    "waiting",
    "scheduled",
  ].includes(result.executionStatus)
    ? result.executionStatus
    : "unavailable",
  code:
    result.data?.error === undefined && result.outer?.data?.type === undefined
      ? "none"
      : safeFullCode(result.data?.error ?? result.outer?.data?.type),
});
export function authCooldown(result, now = Date.now()) {
  let delay = null;
  if (typeof result.retryAfter === "string" && /^\d+$/.test(result.retryAfter))
    delay = Number(result.retryAfter) * 1000;
  else if (result.retryAfter && Number.isFinite(Date.parse(result.retryAfter)))
    delay = Math.max(0, Date.parse(result.retryAfter) - now);
  else if (result.rateLimitReset && /^\d+$/.test(result.rateLimitReset))
    delay = Math.max(0, Number(result.rateLimitReset) * 1000 - now);
  if (delay === null || !Number.isFinite(delay))
    throw new FullProbeError("auth_rate_limit_cooldown_unknown");
  return Math.ceil(delay) + 250;
}
export async function authRequest(
  client,
  method,
  path,
  body,
  {
    allowCooldown = false,
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    now = Date.now,
  } = {},
) {
  let waited = 0;
  for (let attempt = 0; attempt < 3; attempt++) {
    const result = await client.request(method, path, body);
    if (result.status !== 429 || !allowCooldown) return result;
    if (attempt === 2)
      throw new FullProbeError("auth_rate_limit_attempts_exhausted", {
        httpStatus: 429,
      });
    const delay = authCooldown(result, now());
    if (waited + delay > 120000)
      throw new FullProbeError("auth_rate_limit_wait_budget_exceeded", {
        httpStatus: 429,
      });
    waited += delay;
    await sleep(delay);
  }
  throw new FullProbeError("auth_rate_limit_attempts_exhausted");
}
