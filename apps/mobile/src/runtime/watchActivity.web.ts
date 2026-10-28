import { webWatchActivity } from "./invalidationActivity";
export function createWatchActivity() {
  return webWatchActivity(
    typeof document !== "undefined" &&
      typeof window !== "undefined" &&
      typeof navigator !== "undefined"
      ? { document, window, navigator }
      : null,
  );
}
