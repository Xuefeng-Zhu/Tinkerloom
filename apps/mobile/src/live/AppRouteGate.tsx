import type { ReactNode } from "react";
import { Redirect } from "expo-router";
import { Text, View } from "react-native";
import { AppScreen } from "../../App";
import { Button } from "../components/Button";
import { useAppContext } from "../state/AppContext";
import { useAppEngine } from "../state/useAppEngine";
import { styles } from "./LiveAppScreen";
export function AppRouteGate({
  appId,
  build = false,
  children,
}: {
  appId: string;
  build?: boolean;
  children: ReactNode;
}) {
  const context = useAppContext();
  const { engine, error, reload } = useAppEngine(appId);
  if (!appId)
    return (
      <View style={styles.content}>
        <Text style={styles.title}>This app is unavailable</Text>
      </View>
    );
  if (context.state?.phase !== "signedIn" || context.state.authBusy)
    return <AppScreen />;
  if (engine === "appspec.v1")
    return (
      <Redirect
        href={{
          pathname: "/apps/[appId]/full",
          params: { appId, ...(build ? { mode: "build" } : {}) },
        }}
      />
    );
  if (engine === "bounded.v1") return children;
  return (
    <View style={styles.content}>
      <Text style={styles.title}>
        {error ?? "Checking current app access…"}
      </Text>
      {error && <Button label="Try again" onPress={reload} />}
    </View>
  );
}
