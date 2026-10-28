import { router, useLocalSearchParams } from "expo-router";
import { ScrollView, Text } from "react-native";
import { AppScreen } from "../../../App";
import { Button } from "../../components/Button";
import { Notice } from "../../components/Notice";
import { styles } from "../../live/LiveAppScreen";
import { isInvitationToken } from "../../sharing/invitationToken";
import { useInvitation } from "../../sharing/useSharing";

export default function InvitationRoute() {
  const params = useLocalSearchParams<{ token?: string | string[] }>();
  const token = isInvitationToken(params.token) ? params.token : "";
  const { controller, state } = useInvitation(token);
  if (!token)
    return (
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.title}>Invitation unavailable</Text>
        <Button label="Go to workbench" onPress={() => router.replace("/")} />
      </ScrollView>
    );
  if (!controller || !state) return <AppScreen />;
  return (
    <ScrollView contentContainerStyle={styles.content}>
      <Button
        label="← Workbench"
        variant="quiet"
        onPress={() => router.replace("/")}
      />
      <Text style={styles.eyebrow}>A SHARED LITTLE SPACE</Text>
      <Text accessibilityRole="header" style={styles.title}>
        {state.preview?.appName ?? "Review invitation"}
      </Text>
      {state.error && <Notice error text={state.error} />}
      {state.loading && (
        <Text style={styles.body}>Checking this invitation…</Text>
      )}
      {state.preview && (
        <>
          <Text style={styles.body}>
            You are invited as a {state.preview.role}. Expires{" "}
            {new Date(state.preview.expiresAt).toLocaleString()}.
          </Text>
          {!state.appId && (
            <Text style={styles.body}>
              Accepting opens this shared app in your workspace list. Signing in
              alone does not accept the invitation.
            </Text>
          )}
        </>
      )}
      {state.appId ? (
        <Button
          label="Open shared app"
          onPress={() =>
            router.replace({
              pathname: "/apps/[appId]",
              params: { appId: state.appId! },
            })
          }
        />
      ) : state.pending ? (
        <>
          <Text style={styles.body}>
            {state.busy
              ? "Accepting invitation…"
              : "Acceptance is unconfirmed. Retry the original request to check its outcome."}
          </Text>
          {!state.busy && (
            <Button
              label="Retry same acceptance"
              onPress={() => {
                void controller.retry();
              }}
            />
          )}
        </>
      ) : (
        <Button
          label="Accept invitation"
          disabled={!state.preview || state.busy || state.loading}
          onPress={() => {
            void controller.accept();
          }}
        />
      )}
      {!state.busy && (
        <Button
          label="Check invitation again"
          variant="quiet"
          onPress={() => {
            void controller.load();
          }}
        />
      )}
    </ScrollView>
  );
}
