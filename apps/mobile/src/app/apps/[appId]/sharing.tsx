import { router, useLocalSearchParams } from "expo-router";
import { AppScreen } from "../../../../App";
import { SharingScreen } from "../../../sharing/SharingScreen";
import { useSharing } from "../../../sharing/useSharing";

export default function SharingRoute() {
  const params = useLocalSearchParams<{ appId?: string | string[] }>();
  const appId =
    typeof params.appId === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(params.appId)
      ? params.appId
      : "";
  const { controller, state, userId } = useSharing(appId);
  if (!controller || !state || !userId) return <AppScreen />;
  return (
    <SharingScreen
      controller={controller}
      state={state}
      userId={userId}
      onActivity={() =>
        router.push({ pathname: "/apps/[appId]/activity", params: { appId } })
      }
      onBack={() =>
        router.replace({ pathname: "/apps/[appId]", params: { appId } })
      }
    />
  );
}
