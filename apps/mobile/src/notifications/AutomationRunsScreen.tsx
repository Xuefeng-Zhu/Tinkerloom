import { useEffect, useSyncExternalStore } from "react";
import { ScrollView, Text, View } from "react-native";
import { Button } from "../components/Button";
import { Notice } from "../components/Notice";
import { Card, styles } from "../full/ui";
import type { AutomationRunsController } from "./AutomationRunsController";
import type { AutomationRun } from "./contracts";
export function runStatusLabel(run: AutomationRun) {
  return run.status === "pending"
    ? "Pending"
    : run.status === "failed"
      ? "Delivery failed"
      : run.status === "suppressed"
        ? "Suppressed"
        : run.recipientCount === 0
          ? "Completed · no recipients"
          : `Delivered in app · ${run.recipientCount} recipient${run.recipientCount === 1 ? "" : "s"}`;
}
export function AutomationRunsScreen({
  controller,
  onBack,
}: {
  controller: AutomationRunsController;
  onBack: () => void;
}) {
  const state = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
    controller.getSnapshot,
  );
  useEffect(() => {
    void controller.load();
  }, [controller]);
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.row}>
        <Button label="Back to app" variant="quiet" onPress={onBack} />
        <View style={{ flex: 1 }}>
          <Text style={styles.label}>Tinkerloom · Builder</Text>
          <Text accessibilityRole="header" style={styles.heading}>
            Automation runs
          </Text>
        </View>
        <Button
          label="Refresh runs"
          variant="secondary"
          disabled={state.loading}
          onPress={() => {
            void controller.load();
          }}
        />
      </View>
      <Text style={styles.body}>
        Current builder access is checked by the backend on every page. Run
        history reports in-app processing; it does not prove push or email
        delivery.
      </Text>
      {state.error && <Notice text={state.error} error />}
      {state.denied && (
        <Notice text="Run history is hidden because current builder access could not be confirmed." />
      )}
      {state.loading && (
        <Text accessibilityLiveRegion="polite" style={styles.muted}>
          Loading run history…
        </Text>
      )}
      {!state.loading && !state.denied && state.runs.length === 0 && (
        <Card title="No runs yet">
          <Text style={styles.body}>
            Requested reminders do not create runs until they are explicitly
            approved and eligible records are enrolled.
          </Text>
        </Card>
      )}
      {state.runs.map((run) => (
        <Card key={run.id} title={runStatusLabel(run)}>
          <Text style={styles.body}>
            Rule {run.ruleId ?? "unavailable"} · Record {run.recordId}
          </Text>
          <Text style={styles.muted}>
            Due {new Date(run.dueAt).toLocaleString()}
            {"\n"}Attempts {run.attempts} of 5
            {run.status === "pending"
              ? `\nNext attempt no earlier than ${new Date(run.nextAttemptAt).toLocaleString()}`
              : ""}
          </Text>
          {run.errorCategory && (
            <Notice
              text={`Failure category: ${run.errorCategory}`}
              error={run.status === "failed"}
            />
          )}
          <Text selectable style={styles.muted}>
            Run {run.id}
          </Text>
        </Card>
      ))}
      {state.cursor && (
        <Button
          label="Load more runs"
          variant="secondary"
          disabled={state.loading}
          onPress={() => {
            void controller.load(true);
          }}
        />
      )}
      {state.cursor && (
        <Text style={styles.muted}>
          Loaded run history only; more pages are available. No global totals
          are shown.
        </Text>
      )}
    </ScrollView>
  );
}
