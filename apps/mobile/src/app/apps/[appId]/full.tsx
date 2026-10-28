import { router, useLocalSearchParams } from "expo-router";
import { Text, View } from "react-native";
import { AppScreen } from "../../../../App";
import { FullAppScreen } from "../../../full/FullAppScreen";
import { useFullApp } from "../../../full/useFullApp";
import { styles } from "../../../full/ui";
import { useAppContext } from "../../../state/AppContext";
export default function FullAppRoute() {
  const params = useLocalSearchParams<{ appId?: string; mode?: string }>();
  const appId =
    typeof params.appId === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(params.appId)
      ? params.appId
      : "";
  const controller = useFullApp(appId);
  const context = useAppContext();
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
      initialMode={params.mode === "build" ? "build" : "live"}
      onBack={() => router.replace("/")}
      onShare={() =>
        router.push({ pathname: "/apps/[appId]/sharing", params: { appId } })
      }
    />
  );
}
