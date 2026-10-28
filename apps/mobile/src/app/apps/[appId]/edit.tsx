import { router, useLocalSearchParams } from "expo-router";
import { Text, View } from "react-native";
import { AppScreen } from "../../../../App";
import { BuilderScreen } from "../../../live/BuilderScreen";
import { styles } from "../../../live/LiveAppScreen";
import { AppRouteGate } from "../../../live/AppRouteGate";
import { useLiveApp } from "../../../live/useLiveApp";

export default function BuilderRoute() {
  const params = useLocalSearchParams<{ appId?: string | string[] }>();
  const appId =
    typeof params.appId === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(params.appId)
      ? params.appId
      : "";
  return (
    <AppRouteGate appId={appId} build>
      <BoundedRoute appId={appId} />
    </AppRouteGate>
  );
}
function BoundedRoute({ appId }: { appId: string }) {
  const { controller, state } = useLiveApp(appId);
  if (!appId)
    return (
      <View style={styles.content}>
        <Text style={styles.title}>This app is unavailable</Text>
      </View>
    );
  if (!controller || !state) return <AppScreen />;
  return (
    <BuilderScreen
      controller={controller}
      state={state}
      onBack={() =>
        router.dismissTo({ pathname: "/apps/[appId]", params: { appId } })
      }
    />
  );
}
