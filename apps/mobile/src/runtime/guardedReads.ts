import { ensure, RuntimeError } from "./errors";
import { freezeValidated } from "./immutable";
import { runtimeJsonSnapshot } from "./json";
import type { RuntimeReadContext, RuntimeTransport } from "./types";

// These authenticated reads stage the same app/workspace authority guards.
// Mutations, providers, media and unknown operations always bypass this lane.
const guardedReads = new Set([
  "spec.getApp",
  "spec.review",
  "spec.getGeneration",
  "spec.watch",
  "spec.query",
  "spec.getRecord",
  "spec.summary",
  "spec.aggregate",
  "spec.launcher",
  "spec.listDrafts",
  "spec.listVersions",
  "spec.getVersion",
  "spec.appAccess",
]);
interface WaitingRead {
  request: Record<string, unknown>;
  dispatch: RuntimeTransport;
  context?: RuntimeReadContext;
  resolve(value: unknown): void;
  reject(error: unknown): void;
}
/** One FIFO per registry account session, shared across apps and workspaces. */
export class GuardedReadCoordinator {
  private waiting: WaitingRead[] = [];
  private running = false;
  private closed = false;
  private assertCurrent(context?: RuntimeReadContext) {
    ensure(
      !this.closed && (context?.isCurrent() ?? true),
      "superseded_read",
      "This read belongs to a closed or superseded view.",
    );
  }
  transport(dispatch: RuntimeTransport): RuntimeTransport {
    return (input, context) => {
      if (!guardedReads.has(String(input.op))) return dispatch(input, context);
      try {
        this.assertCurrent(context);
        ensure(
          this.waiting.length < 128,
          "read_queue_full",
          "Too many app reads are waiting. Try refreshing again.",
        );
        const request = freezeValidated(
          runtimeJsonSnapshot(input) as Record<string, unknown>,
        );
        return new Promise((resolve, reject) => {
          this.waiting.push({ request, dispatch, context, resolve, reject });
          void this.drain();
        });
      } catch (error) {
        return Promise.reject(error);
      }
    };
  }
  private async drain() {
    if (this.running) return;
    this.running = true;
    try {
      while (this.waiting.length) {
        const job = this.waiting.shift()!;
        try {
          this.assertCurrent(job.context);
          // Account transport checks its session here, at actual dispatch.
          const value = await job.dispatch(job.request, job.context);
          this.assertCurrent(job.context);
          job.resolve(value);
        } catch (error) {
          job.reject(error);
        }
      }
    } finally {
      this.running = false;
    }
  }
  dispose() {
    this.closed = true;
    const error = new RuntimeError(
      "superseded_read",
      "This account's queued reads have closed.",
    );
    for (const job of this.waiting.splice(0)) job.reject(error);
  }
}
