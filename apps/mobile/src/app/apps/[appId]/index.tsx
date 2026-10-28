import { router, useLocalSearchParams } from "expo-router";
import { Text, View } from "react-native";
import { AppScreen } from "../../../../App";
import { LiveAppScreen, styles } from "../../../live/LiveAppScreen";
import { useLiveApp } from "../../../live/useLiveApp";

export default function AppRoute() {
  const params = useLocalSearchParams<{ appId?: string | string[] }>();
  const appId =
    typeof params.appId === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(params.appId)
      ? params.appId
      : "";
  const { controller, state } = useLiveApp(appId);
  if (!appId)
    return (
      <View style={styles.content}>
        <Text style={styles.title}>This app is unavailable</Text>
      </View>
    );
  if (!controller || !state) return <AppScreen />;
  return (
    <LiveAppScreen
      controller={controller}
      state={state}
      onBack={() => router.replace("/")}
      onEdit={() =>
        router.push({ pathname: "/apps/[appId]/edit", params: { appId } })
      }
    />
  );
}
