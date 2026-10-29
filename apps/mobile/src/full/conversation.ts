import { ensure } from "../runtime/errors";
import { freezeValidated } from "../runtime/immutable";
import type { Generation } from "./contracts";

export interface AcceptedRequestEntry {
  jobId: string;
  requestText: string;
  mode: Generation["mode"];
  status: Generation["status"];
  mutation: number;
  attempts: number;
  origin: "accepted" | "restored";
  current: boolean;
}
export interface ConversationSnapshot {
  entries: readonly AcceptedRequestEntry[];
  omitted: number;
}
export const CONVERSATION_ENTRY_LIMIT = 50;
export const CONVERSATION_BYTE_LIMIT = 512 * 1024;
const active = (status: Generation["status"]) =>
  ["queued", "generating", "validating"].includes(status);
/** Validate before clearing an exact generation receipt; no provider response/body is retained here. */
export function acceptedRequest(
  job: Generation,
  origin: AcceptedRequestEntry["origin"],
): AcceptedRequestEntry {
  ensure(
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(job.id) &&
      job.requestText.trim().length > 0 &&
      new TextEncoder().encode(job.requestText).byteLength <= 16384,
    "invalid_response",
    "The accepted generation request is invalid.",
  );
  return freezeValidated({
    jobId: job.id,
    requestText: job.requestText,
    mode: job.mode,
    status: job.status,
    mutation: job.mutation,
    attempts: job.attempts,
    origin,
    current: false,
  });
}
/** Account/app/author session memory only. This class has no storage, transport, clock or log. */
export class AcceptedConversation {
  private state: ConversationSnapshot = freezeValidated({
    entries: [],
    omitted: 0,
  });
  getSnapshot = () => this.state;
  clear() {
    this.state = freezeValidated({ entries: [], omitted: 0 });
  }
  contains(jobId: string) {
    return this.state.entries.some((entry) => entry.jobId === jobId);
  }
  accept(job: Generation, origin: AcceptedRequestEntry["origin"]) {
    const next = acceptedRequest(job, origin);
    const found = this.state.entries.find(
      (entry) => entry.jobId === next.jobId,
    );
    if (found) {
      ensure(
        found.requestText === next.requestText &&
          found.mode === next.mode &&
          found.mutation === next.mutation,
        "invalid_response",
        "The generation identity changed its original request.",
      );
      return;
    }
    const entries = [...this.state.entries, next];
    let omitted = this.state.omitted;
    let bytes = entries.reduce(
      (total, entry) =>
        total + new TextEncoder().encode(entry.requestText).byteLength,
      0,
    );
    while (
      entries.length > CONVERSATION_ENTRY_LIMIT ||
      bytes > CONVERSATION_BYTE_LIMIT
    ) {
      const removed = entries.shift()!;
      bytes -= new TextEncoder().encode(removed.requestText).byteLength;
      omitted++;
    }
    this.state = freezeValidated({ entries, omitted });
  }
  /** Only current authorized metadata can advance status. An old receipt is acceptance, not current progress. */
  observe(job: Generation | null) {
    let changed = false;
    const entries = this.state.entries.map((entry) => {
      if (job?.id === entry.jobId) {
        ensure(
          entry.requestText === job.requestText &&
            entry.mode === job.mode &&
            entry.mutation === job.mutation,
          "invalid_response",
          "The generation identity changed its original request.",
        );
        const current = job.status !== "stale";
        if (
          entry.status === job.status &&
          entry.attempts === job.attempts &&
          entry.current === current
        )
          return entry;
        changed = true;
        return {
          ...entry,
          status: job.status,
          attempts: job.attempts,
          current,
        };
      }
      if (!entry.current) return entry;
      changed = true;
      return { ...entry, current: false };
    });
    if (changed) this.state = freezeValidated({ ...this.state, entries });
  }
}
export function conversationOutcome(entry: AcceptedRequestEntry): string {
  if (!entry.current && active(entry.status))
    return "Request accepted earlier. It is no longer the current request; its latest outcome is not loaded.";
  switch (entry.status) {
    case "queued":
      return "Request accepted and queued. No preview has been produced yet.";
    case "generating":
      return "The server reports generation in progress.";
    case "validating":
      return "The server is validating the proposed private declaration.";
    case "preview ready":
      return "This request produced a validated private preview. Publication is a separate action.";
    case "failed":
      return "Generation failed. No version was published by this request.";
    case "stale":
      return "This request was superseded. It cannot replace the current candidate.";
  }
}
