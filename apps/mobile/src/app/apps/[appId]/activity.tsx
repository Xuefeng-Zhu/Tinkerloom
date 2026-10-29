import { useCallback } from "react";
import { router, useFocusEffect, useLocalSearchParams } from "expo-router";
import { Text, View } from "react-native";
import { AppScreen } from "../../../../App";
import { ActivityScreen } from "../../../activity/ActivityScreen";
import { useActivity } from "../../../activity/useActivity";
import { Button } from "../../../components/Button";
import { styles } from "../../../full/ui";
import { useAppContext } from "../../../state/AppContext";

export default function ActivityRoute() {
  const params = useLocalSearchParams<{ appId?: string | string[] }>();
  const appId =
    typeof params.appId === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(params.appId)
      ? params.appId
      : "";
  const controller = useActivity(appId),
    context = useAppContext();
  useFocusEffect(
    useCallback(() => {
      if (!controller) return;
      void controller.load();
      return () => controller.cancelRead();
    }, [controller]),
  );
  if (!controller) {
    if (context.state?.phase !== "signedIn" || context.state.authBusy)
      return <AppScreen />;
    return (
      <View style={styles.content}>
        <Text style={styles.body}>
          Choose an available full app to inspect its activity.
        </Text>
        <Button
          label="Back to workspaces"
          onPress={() => router.replace("/")}
        />
      </View>
    );
  }
  return (
    <ActivityScreen
      controller={controller}
      onBack={() =>
        router.replace({
          pathname: "/apps/[appId]",
          params: { appId },
        })
      }
    />
  );
}
