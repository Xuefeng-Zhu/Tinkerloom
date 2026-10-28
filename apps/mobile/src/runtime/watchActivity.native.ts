import { AppState, Platform } from "react-native";
import { nativeWatchActivity } from "./invalidationActivity";
/** RN0.88 AppState change/focus/blur subscriptions return removable EventSubscriptions. */
export function createWatchActivity() {
  return nativeWatchActivity({
    currentState: () => (AppState.isAvailable ? AppState.currentState : null),
    subscribe(event, notify) {
      if (event !== "change" && Platform.OS !== "android") return () => {};
      const subscription =
        event === "change"
          ? AppState.addEventListener("change", (state) => notify(state))
          : AppState.addEventListener(event, () => notify());
      return () => subscription.remove();
    },
  });
}
