import { router, useLocalSearchParams } from "expo-router";
import { Text, View } from "react-native";
import { AppScreen } from "../../App";
import { Button } from "../components/Button";
import { FullLauncher } from "../full/FullLauncher";
import { useFullWorkspace } from "../full/useFullApp";
import { styles } from "../full/ui";
import { useAppContext } from "../state/AppContext";
export default function WorkbenchRoute() {
  const params = useLocalSearchParams<{ workspaceId?: string }>();
  const context = useAppContext();
  const workspaceId =
    typeof params.workspaceId === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(params.workspaceId)
      ? params.workspaceId
      : "";
  const controller = useFullWorkspace(workspaceId);
  if (!controller) {
    if (context.state?.phase === "signedIn" && !context.state.authBusy)
      return (
        <View style={styles.content}>
          <Text>Choose an available workspace to open its workbench.</Text>
          <Button
            label="Back to workspaces"
            onPress={() => router.replace("/")}
          />
        </View>
      );
    return <AppScreen />;
  }
  const open = (appId: string, full: boolean, build = false) =>
    router.push({
      pathname: full
        ? "/apps/[appId]/full"
        : build
          ? "/apps/[appId]/edit"
          : "/apps/[appId]",
      params: { appId, ...(build && full ? { mode: "build" } : {}) },
    });
  return (
    <View style={styles.screen}>
      <View style={{ padding: 12 }}>
        <Button
          label="Back to workspaces"
          variant="quiet"
          onPress={() => router.replace("/")}
        />
      </View>
      <FullLauncher
        key={`${context.controller?.sessionVersion}:${workspaceId}`}
        controller={controller}
        onOpenApp={(id) => open(id, true)}
        onOpenBoundedApp={(id) => open(id, false)}
        onResumeDraft={(id, engine) => open(id, engine === "appspec.v1", true)}
      />
    </View>
  );
}
