import { BackendError } from "../backend/errors";
import { freezeValidated } from "../runtime/immutable";
import {
  ensure,
  isRuntimeAccessFailure,
  runtimeError,
} from "../runtime/errors";

export interface ClarificationQuestion {
  question: string;
  options: readonly string[];
}
export type ClarificationMode = "create" | "edit";
export type ClarificationFallback =
  "unconfigured" | "unavailable" | "too_long" | "unusable" | "optional";
export interface ClarificationAssessment {
  requestText: string;
  mode: ClarificationMode;
  source: "provider" | "built-in";
  ready: boolean;
  questions: readonly ClarificationQuestion[];
  notice: string;
}
const createQuestions: readonly ClarificationQuestion[] = [
  {
    question: "Who will use this app?",
    options: [
      "Just me",
      "A small team or club",
      "People in my community",
      "Customers or clients",
    ],
  },
  {
    question: "What should it keep track of?",
    options: [
      "Tasks and due dates",
      "Events and attendance",
      "Members and contacts",
      "Notes and updates",
    ],
  },
  {
    question: "What should people do most often?",
    options: [
      "Add and update entries",
      "Plan and schedule",
      "Share and discuss",
      "View progress",
    ],
  },
];
const editQuestions: readonly ClarificationQuestion[] = [
  {
    question: "What should change first?",
    options: [
      "Layout and navigation",
      "Fields and forms",
      "Colors and wording",
      "Rules or reminders",
    ],
  },
  {
    question: "Who should this change help most?",
    options: [
      "App owners",
      "People adding records",
      "People viewing records",
      "Everyone",
    ],
  },
  {
    question: "How much should change?",
    options: [
      "One screen or section",
      "Several screens",
      "Only the appearance",
      "I am not sure yet",
    ],
  },
];
const fallbackNotices: Record<ClarificationFallback, string> = {
  unconfigured:
    "Provider clarification is not configured. These built-in questions work locally; choose what fits or continue with your original request.",
  unavailable:
    "Provider clarification is unavailable right now. These built-in questions work locally; choose what fits or continue with your original request.",
  too_long:
    "This request exceeds the provider clarification limit of 2,000 characters or 4,000 bytes. These built-in questions work locally; your original text is unchanged.",
  unusable:
    "The provider's questions could not be used. These built-in questions work locally; your original text is unchanged.",
  optional:
    "Optional built-in questions. Choose what fits, skip any question, or continue with your original request.",
};
export function canAssessClarification(request: string) {
  return (
    request.length <= 2000 &&
    new TextEncoder().encode(request).byteLength <= 4000
  );
}
export function builtInClarification(
  requestText: string,
  mode: ClarificationMode,
  reason: ClarificationFallback,
): ClarificationAssessment {
  return freezeValidated({
    requestText,
    mode,
    source: "built-in",
    ready: false,
    questions: mode === "edit" ? editQuestions : createQuestions,
    notice: fallbackNotices[reason],
  });
}
/** Empty is an explicit ready result; any unusable nonempty provider answer falls back. */
export function cleanClarificationQuestions(
  value: unknown,
): ClarificationQuestion[] | null {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    !Object.hasOwn(value, "questions")
  )
    return null;
  const items = (value as { questions?: unknown }).questions;
  if (!Array.isArray(items)) return null;
  if (items.length === 0) return [];
  if (items.length < 2 || items.length > 3) return null;
  const seen = new Set<string>();
  const questions: ClarificationQuestion[] = [];
  for (const item of items) {
    if (
      !item ||
      typeof item !== "object" ||
      Array.isArray(item) ||
      typeof item.question !== "string" ||
      !Array.isArray(item.options) ||
      !item.options.every((v: unknown) => typeof v === "string")
    )
      return null;
    const question = item.question.trim();
    const options = (item.options as string[]).map((v) => v.trim());
    if (
      question.length < 8 ||
      question.length > 120 ||
      !question.endsWith("?") ||
      seen.has(question.toLowerCase()) ||
      options.length < 3 ||
      options.length > 4 ||
      options.some((v) => v.length < 2 || v.length > 80) ||
      new Set(options.map((v) => v.toLowerCase())).size !== options.length
    )
      return null;
    seen.add(question.toLowerCase());
    questions.push({ question, options });
  }
  return questions;
}
export function clarificationAccessFailure(error: unknown) {
  const failure = runtimeError(error);
  return (
    isRuntimeAccessFailure(failure) ||
    failure.code === "not_found" ||
    failure.code === "session_changed" ||
    (error instanceof BackendError && error.status === 404)
  );
}
function fallbackReason(error: unknown): ClarificationFallback | null {
  const failure = runtimeError(error);
  if (failure.code === "invalid_response") return "unusable";
  return [
    "provider_unavailable",
    "quota_exceeded",
    "connection_failed",
    "read_failed",
    "transaction_conflict",
    "timeout",
  ].includes(failure.code)
    ? "unavailable"
    : null;
}
/** Read-only optional guidance. No app creation, generation, replay, journal or record IO occurs here. */
export async function assessClarification(options: {
  request: string;
  mode: ClarificationMode;
  providerEnabled: boolean | null | (() => Promise<boolean>);
  askProvider: () => Promise<unknown>;
  isCurrent: () => boolean;
  isAlive: () => boolean;
}): Promise<ClarificationAssessment | null> {
  const { request, mode } = options;
  ensure(
    request.trim().length > 0,
    "invalid_input",
    "Describe your idea before asking for help.",
  );
  if (!options.isAlive() || !options.isCurrent()) return null;
  if (!canAssessClarification(request))
    return builtInClarification(request, mode, "too_long");
  try {
    const enabled =
      typeof options.providerEnabled === "function"
        ? await options.providerEnabled()
        : options.providerEnabled;
    if (!options.isAlive() || !options.isCurrent()) return null;
    if (!enabled)
      return builtInClarification(
        request,
        mode,
        enabled === false ? "unconfigured" : "unavailable",
      );
    const response = await options.askProvider();
    if (!options.isAlive() || !options.isCurrent()) return null;
    const questions = cleanClarificationQuestions(response);
    if (questions === null)
      return builtInClarification(request, mode, "unusable");
    return freezeValidated({
      requestText: request,
      mode,
      source: "provider",
      ready: questions.length === 0,
      questions,
      notice:
        questions.length === 0
          ? "The provider found your request actionable. You can continue with the original request, or explore optional built-in questions. Nothing has been created or generated."
          : "Choose at most one answer per question; any question can be skipped. Selections stay local until you use them, then you can edit the request before submitting.",
    });
  } catch (error) {
    if (!options.isAlive()) return null;
    // Current access denials remain authoritative even if the composer changed.
    if (clarificationAccessFailure(error)) throw error;
    if (!options.isCurrent()) return null;
    const reason = fallbackReason(error);
    if (!reason) throw error;
    return builtInClarification(request, mode, reason);
  }
}
export type ClarificationSelections = Readonly<Record<number, number>>;
export function selectClarificationAnswer(
  assessment: ClarificationAssessment,
  selections: ClarificationSelections,
  question: number,
  option: number,
): ClarificationSelections {
  ensure(
    Number.isSafeInteger(question) &&
      Number.isSafeInteger(option) &&
      !!assessment.questions[question]?.options[option],
    "invalid_input",
    "Choose an available answer.",
  );
  const next = { ...selections };
  next[question] = option;
  return Object.freeze(next);
}
export function originalClarificationRequest(
  assessment: ClarificationAssessment,
  currentRequest: string,
) {
  ensure(
    currentRequest === assessment.requestText,
    "request_changed",
    "Your request changed. Ask for fresh questions.",
  );
  return assessment.requestText;
}
export function applyClarificationSelections(
  assessment: ClarificationAssessment,
  currentRequest: string,
  selections: ClarificationSelections,
) {
  const original = originalClarificationRequest(assessment, currentRequest);
  const answers = assessment.questions.flatMap((q, i) => {
    if (!Object.hasOwn(selections, i)) return [];
    const option = selections[i];
    ensure(
      Number.isSafeInteger(option) && typeof q.options[option] === "string",
      "invalid_input",
      "Choose an available answer.",
    );
    return [`- ${q.question} ${q.options[option]}`];
  });
  ensure(
    answers.length > 0,
    "invalid_input",
    "Choose at least one option, or continue with the original request.",
  );
  const combined = `${original}\n\nMore details:\n${answers.join("\n")}`;
  ensure(
    new TextEncoder().encode(combined).byteLength <= 16384,
    "invalid_input",
    "These choices exceed the 16 KiB generation request limit. Continue with the original request or shorten it.",
  );
  return combined;
}
