import { useSyncExternalStore } from "react";
import { ScrollView, Text, View } from "react-native";
import { Button } from "../components/Button";
import { Notice } from "../components/Notice";
import { Card, styles } from "../full/ui";
import type { ActivityController } from "./ActivityController";
import { activityLabel } from "./contracts";

export function ActivityScreen({
  controller,
  onBack,
}: {
  controller: ActivityController;
  onBack: () => void;
}) {
  const state = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
    controller.getSnapshot,
  );
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.row}>
        <Button label="Back to app" variant="quiet" onPress={onBack} />
        <View style={{ flex: 1 }}>
          <Text style={styles.label}>Tinkerloom</Text>
          <Text accessibilityRole="header" style={styles.heading}>
            App activity
          </Text>
        </View>
        <Button
          label="Refresh activity"
          variant="secondary"
          disabled={state.loading}
          onPress={() => {
            void controller.load();
          }}
        />
      </View>
      <Text style={styles.body}>
        Committed app changes, shown in a stable entry order. Times use your
        device’s locale. Refresh checks your current access.
      </Text>
      {state.error && <Notice text={state.error} error />}
      {state.loading && (
        <Text accessibilityLiveRegion="polite" style={styles.muted}>
          Loading activity…
        </Text>
      )}
      {!state.loading &&
        !state.items.length &&
        !state.denied &&
        !state.error && (
          <Card title="No committed activity">
            <Text style={styles.body}>
              App changes will appear here after they commit.
            </Text>
          </Card>
        )}
      {state.items.map((entry) => (
        <Card key={entry.id} title={activityLabel(entry.action)}>
          <Text style={styles.body}>
            {new Date(entry.createdAt).toLocaleString()}
          </Text>
          <Text style={styles.muted}>Committed</Text>
        </Card>
      ))}
      {state.items.length > 0 && (
        <Text style={styles.muted}>
          {state.items.length} loaded activity entries.
        </Text>
      )}
      {state.cursor && (
        <Button
          label="Load more activity"
          variant="secondary"
          disabled={state.loading}
          onPress={() => {
            void controller.load(true);
          }}
        />
      )}
    </ScrollView>
  );
}
