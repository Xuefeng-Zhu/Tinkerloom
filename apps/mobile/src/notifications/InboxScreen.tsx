import { useEffect, useState, useSyncExternalStore } from "react";
import { ScrollView, Text, View } from "react-native";
import { Button } from "../components/Button";
import { Notice } from "../components/Notice";
import { Card, styles } from "../full/ui";
import type { NotificationsServices } from "./NotificationsContext";
export function InboxScreen({
  services,
  onBack,
}: {
  services: NotificationsServices;
  onBack: () => void;
}) {
  const controller = services.inbox,
    state = useSyncExternalStore(
      controller.subscribe,
      controller.getSnapshot,
      controller.getSnapshot,
    ),
    [openError, setOpenError] = useState<string | null>(null);
  useEffect(() => {
    void controller.load();
  }, [controller]);
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.row}>
        <Button label="Back to workspaces" variant="quiet" onPress={onBack} />
        <View style={{ flex: 1 }}>
          <Text style={styles.label}>Tinkerloom</Text>
          <Text accessibilityRole="header" style={styles.heading}>
            Your inbox
          </Text>
        </View>
        <Button
          label="Refresh inbox"
          variant="secondary"
          disabled={state.loading}
          onPress={() => {
            void controller.load();
          }}
        />
      </View>
      <Text style={styles.body}>
        In-app reminders addressed to your account. Opening a record checks its
        current app and record access. Refresh to check for new notifications.
      </Text>
      {(state.error || openError) && (
        <Notice text={openError ?? state.error!} error />
      )}
      {state.pending && (
        <Card title="Read receipt retained">
          <Text style={styles.body}>
            {state.phase === "sending"
              ? "Saving read status…"
              : state.phase === "uncertain"
                ? "The original read receipt has an unconfirmed outcome."
                : "The backend rejected the original read receipt."}
          </Text>
          <Text style={styles.muted}>
            The exact notification and operation are saved for this account.
            Refreshing or leaving never replays the write automatically.
          </Text>
          {state.phase === "uncertain" && (
            <Button
              label="Check original read receipt"
              disabled={state.busy}
              onPress={() => {
                void controller.retry();
              }}
            />
          )}
          {state.phase === "rejected" && (
            <Button
              label="Acknowledge definitive rejection"
              variant="secondary"
              disabled={state.busy}
              onPress={() => {
                void controller.acknowledgeRejection();
              }}
            />
          )}
        </Card>
      )}
      {state.loading && (
        <Text accessibilityLiveRegion="polite" style={styles.muted}>
          Loading current notifications…
        </Text>
      )}
      {state.items.length === 0 && !state.loading && (
        <Card title="Nothing to read yet">
          <Text style={styles.body}>
            Your authorized in-app reminders will appear here after delivery. An
            empty inbox does not indicate whether a requested reminder is
            enabled.
          </Text>
        </Card>
      )}
      {state.items.map((item) => (
        <Card key={item.id} title={item.title}>
          <Text style={styles.body}>{item.body}</Text>
          <Text style={styles.muted}>
            {new Date(item.createdAt).toLocaleString()} ·{" "}
            {item.isRead ? "Read" : "Unread"}
          </Text>
          {item.recordId === null ? (
            <Text style={styles.muted}>The current record is unavailable.</Text>
          ) : (
            <Button
              label="Open current record"
              variant="secondary"
              busy={state.openingId === item.id}
              disabled={state.openingId !== null}
              onPress={() => {
                setOpenError(null);
                void controller
                  .openTarget(
                    item,
                    services.resolveRuntime,
                    services.openTarget,
                  )
                  .catch(() =>
                    setOpenError(
                      "The current record could not be opened. Refresh and check its app access.",
                    ),
                  );
              }}
            />
          )}
          <Button
            label={item.isRead ? "Marked read" : "Mark as read"}
            variant="quiet"
            disabled={item.isRead || state.busy || state.pending !== null}
            onPress={() => {
              void controller.markRead(item);
            }}
          />
        </Card>
      ))}
      {state.cursor && (
        <Button
          label="Load more notifications"
          variant="secondary"
          disabled={state.loading}
          onPress={() => {
            void controller.load(true);
          }}
        />
      )}
      {state.cursor && (
        <Text style={styles.muted}>
          Showing loaded notifications only. More are available.
        </Text>
      )}
    </ScrollView>
  );
}
