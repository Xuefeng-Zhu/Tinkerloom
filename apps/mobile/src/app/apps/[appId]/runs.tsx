import { useMemo } from "react";
import { router, useLocalSearchParams } from "expo-router";
import { Text, View } from "react-native";
import { Button } from "../../../components/Button";
import { styles } from "../../../full/ui";
import { AutomationRunsScreen } from "../../../notifications/AutomationRunsScreen";
import { useNotifications } from "../../../notifications/NotificationsContext";
export default function RunsRoute() {
  const params = useLocalSearchParams<{ appId?: string }>(),
    services = useNotifications();
  const appId =
    typeof params.appId === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(params.appId)
      ? params.appId
      : "";
  const controller = useMemo(
    () => (services && appId ? services.runs(appId) : null),
    [services, appId],
  );
  if (!controller)
    return (
      <View style={styles.content}>
        <Text style={styles.body}>
          Sign in and open an available app to inspect its automation runs.
        </Text>
        <Button
          label="Back to workspaces"
          onPress={() => router.replace("/")}
        />
      </View>
    );
  return (
    <AutomationRunsScreen
      controller={controller}
      onBack={() =>
        router.replace({ pathname: "/apps/[appId]/full", params: { appId } })
      }
    />
  );
}
