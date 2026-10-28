import { router } from "expo-router";
import { Text, View } from "react-native";
import { Button } from "../components/Button";
import { styles } from "../full/ui";
import { InboxScreen } from "../notifications/InboxScreen";
import { useNotifications } from "../notifications/NotificationsContext";
export default function InboxRoute() {
  const services = useNotifications();
  return services ? (
    <InboxScreen services={services} onBack={() => router.replace("/")} />
  ) : (
    <View style={styles.content}>
      <Text style={styles.body}>
        Sign in to open your account’s inbox. Notifications must be connected to
        the current account session.
      </Text>
      <Button label="Back to workspaces" onPress={() => router.replace("/")} />
    </View>
  );
}
