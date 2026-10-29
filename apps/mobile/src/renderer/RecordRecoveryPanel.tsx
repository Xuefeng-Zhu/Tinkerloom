import { useLayoutEffect, useState, useSyncExternalStore } from "react";
import { StyleSheet, Text, View } from "react-native";
import type { RuntimeController } from "../runtime/controller";
import { Button } from "../components/Button";
import { Notice } from "../components/Notice";
import { colors, space } from "../components/theme";
import {
  performRecordRecovery,
  recordRecoveryPresentation,
  RecordRecoveryGate,
} from "./recordRecovery";
/** Shared host recovery UI; it never creates a controller, command, ID, query or automatic retry. */
export function RecordRecoveryPanel({
  controller,
}: {
  controller: RuntimeController;
}) {
  const state = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
    controller.getSnapshot,
  );
  const presentation = recordRecoveryPresentation(state);
  const [gate] = useState(() => new RecordRecoveryGate());
  const activity = useSyncExternalStore(
    gate.subscribe,
    gate.getSnapshot,
    gate.getSnapshot,
  );
  const busy = activity.owner === controller && activity.busy;
  useLayoutEffect(() => gate.attach(controller), [gate, controller]);
  if (!presentation) return null;
  const run = async () => {
    const action = presentation.action;
    if (!action || activity.owner !== controller || !activity.token) return;
    try {
      await gate.run(activity.token, () =>
        performRecordRecovery(controller, presentation.operationId, action),
      );
    } catch {
      /* Scope/command changes can invalidate an already rendered control; current controller state owns the visible result. */
    }
  };
  return (
    <View style={styles.panel}>
      <Text
        accessibilityRole="header"
        accessibilityLiveRegion="polite"
        style={styles.title}
      >
        {presentation.title}
      </Text>
      <Notice
        text={presentation.message}
        error={presentation.status !== "sending"}
      />
      {presentation.action === "retry" ? (
        <>
          <Text style={styles.body}>
            Retry may apply the original change if it never completed, using its
            saved operation ID, values, published version and record revision.
          </Text>
          <Button
            label="Retry original record request"
            busy={busy}
            onPress={() => {
              void run();
            }}
          />
        </>
      ) : presentation.action === "acknowledge" ? (
        <>
          <Text style={styles.body}>
            Acknowledge the definite failure to clear this recovery entry before
            continuing.
          </Text>
          <Button
            label="Acknowledge record failure"
            variant="secondary"
            busy={busy}
            onPress={() => {
              void run();
            }}
          />
        </>
      ) : null}
    </View>
  );
}
const styles = StyleSheet.create({
  panel: {
    padding: space.md,
    gap: space.sm,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    backgroundColor: colors.surface,
  },
  title: { fontSize: 20, lineHeight: 27, fontWeight: "600", color: colors.ink },
  body: { fontSize: 14, lineHeight: 21, color: colors.ink },
});
