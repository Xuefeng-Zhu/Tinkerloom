import { router } from "expo-router";
import { InvitationEntryScreen } from "../../screens/InvitationEntryScreen";

export default function InvitationEntryRoute() {
  return (
    <InvitationEntryScreen
      onReview={(token) =>
        router.replace({ pathname: "/invite/[token]", params: { token } })
      }
      onBack={() => {
        if (router.canGoBack()) router.back();
        else router.replace("/");
      }}
    />
  );
}
