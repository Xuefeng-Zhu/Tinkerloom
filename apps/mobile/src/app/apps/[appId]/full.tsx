import { useCallback, useMemo, useSyncExternalStore } from "react";
import {
  router,
  useIsFocused,
  useLocalSearchParams,
  useNavigation,
  useRoute,
} from "expo-router";
import { Text, View } from "react-native";
import { AppScreen } from "../../../../App";
import { FullAppScreen } from "../../../full/FullAppScreen";
import type { FullAppController } from "../../../full/FullAppController";
import {
  FullRouteVisits,
  fullRouteParams,
  parseFullRoute,
} from "../../../full/navigation";
import type { FullMode } from "../../../full/navigation";
import type { RuntimeLocation } from "../../../runtime/types";
import { useFullApp } from "../../../full/useFullApp";
import { styles } from "../../../full/ui";
import { useAppContext } from "../../../state/AppContext";

const noProtectionSubscription = () => () => {};
const noProtectionSnapshot = () => null;
const visitsByController = new WeakMap<FullAppController, FullRouteVisits>();
export default function FullAppRoute() {
  const params = useLocalSearchParams<{
    appId?: string;
    mode?: string;
    page?: string;
    recordId?: string;
    edit?: string;
  }>();
  const appId =
    typeof params.appId === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(params.appId)
      ? params.appId
      : "";
  const controller = useFullApp(appId);
  const context = useAppContext();
  const navigation = useNavigation();
  const focused = useIsFocused();
  const routeKey = useRoute().key;
  const visits = useMemo(() => {
    if (!controller) return null;
    let current = visitsByController.get(controller);
    if (!current) {
      current = new FullRouteVisits();
      visitsByController.set(controller, current);
    }
    return current;
  }, [controller]);
  const protection = useSyncExternalStore(
    visits?.subscribe ?? noProtectionSubscription,
    visits?.getProtection ?? noProtectionSnapshot,
    visits?.getProtection ?? noProtectionSnapshot,
  );
  const protectedLocationOwned =
    !protection?.ownerKey || protection.ownerKey === routeKey;
  const protectLocation = useCallback(
    (locked: boolean) => {
      const state = navigation.getState();
      if (
        !focused ||
        !controller?.host.lifetime.active ||
        state?.routes[state.index]?.key !== routeKey
      )
        return;
      visits?.protect(routeKey, locked);
    },
    [controller, focused, navigation, routeKey, visits],
  );
  const restoreProtectedLocation = useCallback(
    (request: ReturnType<typeof parseFullRoute>) => {
      if (!focused || !controller?.host.lifetime.active || !visits)
        return "unavailable" as const;
      const state = navigation.getState();
      if (!state || state.routes[state.index]?.key !== routeKey)
        return "unavailable" as const;
      const count = visits.protectedReturnCount(
        routeKey,
        state.routes.slice(0, state.index + 1).map((item) => item.key),
      );
      if (count === 0) return "current" as const;
      if (count === null) return "unavailable" as const;
      const owner = visits.getProtection().ownerKey;
      const attempt = visits.defer(request);
      const latest = navigation.getState();
      if (
        !controller.host.lifetime.active ||
        !latest ||
        latest.index !== state.index ||
        latest.routes[latest.index]?.key !== routeKey ||
        latest.routes[latest.index - count]?.key !== owner ||
        visits.getProtection().ownerKey !== owner
      ) {
        visits.dismissAttempt(attempt.id);
        return "unavailable" as const;
      }
      router.dismiss(count);
      return "restored" as const;
    },
    [controller, focused, navigation, routeKey, visits],
  );
  const dismissExternalAttempt = useCallback(
    (id: number) => visits?.dismissAttempt(id),
    [visits],
  );
  const route = useMemo(
    () =>
      parseFullRoute({
        page: params.page,
        recordId: params.recordId,
        edit: params.edit,
        mode: params.mode,
      }),
    [params.page, params.recordId, params.edit, params.mode],
  );
  const locationChanged = useCallback(
    (
      location: RuntimeLocation,
      kind: "push" | "pop" | "replace",
      mode: FullMode,
    ) => {
      if (!focused || !controller?.host.lifetime.active || !visits) return;
      const state = navigation.getState();
      const current = state?.routes[state.index];
      if (current?.key !== routeKey) return;
      const previous =
        state && state.index > 0 ? state.routes[state.index - 1] : undefined;
      const href = {
        pathname: "/apps/[appId]/full" as const,
        params: fullRouteParams(appId, location, mode),
      };
      if (
        kind === "pop" &&
        previous &&
        visits.owns(previous.key, location, mode)
      ) {
        router.back();
      } else if (kind === "push") {
        // A distinct visit gives Expo Router a tracked browser/native Back entry.
        router.push(href);
      } else {
        // Direct-link/native fallback has no owned parent entry to traverse.
        if (current) visits.remember(current.key, location, mode);
        router.setParams(href.params);
      }
    },
    [appId, controller, focused, navigation, routeKey, visits],
  );
  if (!appId)
    return (
      <View style={styles.content}>
        <Text>This app is unavailable.</Text>
      </View>
    );
  if (!controller) {
    if (context.state?.phase === "signedIn" && !context.state.authBusy)
      return (
        <View style={styles.content}>
          <Text>The full app service is not configured for this build.</Text>
        </View>
      );
    return <AppScreen />;
  }
  return (
    <FullAppScreen
      key={`${context.controller?.sessionVersion}:${appId}`}
      controller={controller}
      initialMode={route.mode}
      route={route}
      protectedLocationOwned={protectedLocationOwned}
      onProtectionChange={protectLocation}
      onRestoreProtectedLocation={restoreProtectedLocation}
      externalAttempt={
        focused && protectedLocationOwned
          ? (protection?.attempt ?? undefined)
          : undefined
      }
      onDismissExternalAttempt={dismissExternalAttempt}
      onLocationChange={locationChanged}
      onBack={() => router.replace("/")}
      onRuns={() =>
        router.push({ pathname: "/apps/[appId]/runs", params: { appId } })
      }
      onShare={() =>
        router.push({ pathname: "/apps/[appId]/sharing", params: { appId } })
      }
    />
  );
}
