import { useState } from "react";
import { Text, View } from "react-native";
import { Button } from "../components/Button";
import { Field } from "../components/Field";
import { Notice } from "../components/Notice";
import { requestedDeviceCapabilities } from "../spec/bindings";
import type { FullAppController, FullAppState } from "./FullAppController";
import { Card, Toggle, styles } from "./ui";
import { same, type PublicationReview } from "./contracts";
/** The server validates every existing record ID; no sample IDs are preselected or copied. */
export function PublicationPanel({
  controller,
  state,
}: {
  controller: FullAppController;
  state: FullAppState;
}) {
  const [rules, setRules] = useState<string[]>([]),
    [records, setRecords] = useState(""),
    [approvedReview, setApprovedReview] = useState<PublicationReview | null>(
      null,
    );
  const spec = state.candidate,
    review = state.review;
  const approved = review !== null && approvedReview === review;
  const setApproved = (value: boolean) =>
    setApprovedReview(value ? review : null);
  const locked = state.busy || !!state.pending || !controller.canBuild;
  const recordIds = records.split(/[\s,]+/).filter(Boolean);
  const scopeMatches =
    !!review &&
    same([...rules].sort(), review.enabledRuleIds) &&
    same([...recordIds].sort(), review.activateExistingRecordIds);
  return (
    <Card title="Review and publish">
      <Text style={styles.body}>
        Publishing creates an immutable live version. Existing records stay in
        place. Compatibility checks prevent unsupported schema changes; versions
        do not roll records, access or effects back.
      </Text>
      {spec && (
        <>
          <Text style={styles.muted}>
            Policy: {spec.policyPresetRequest} · {spec.collections.length}{" "}
            collections · {spec.views.length} views ·{" "}
            {spec.navigation?.pages.length ?? 1} pages
          </Text>
          {requestedDeviceCapabilities(spec).length > 0 && (
            <Notice
              text={`Requested device features: ${requestedDeviceCapabilities(spec).join(", ")}. Each account grants device consent separately.`}
            />
          )}
          <Text style={styles.title}>Reminder approval</Text>
          {spec.automationRequests.length === 0 ? (
            <Text style={styles.muted}>No requested reminders.</Text>
          ) : (
            spec.automationRequests.map((rule) => {
              const supported =
                state.platform?.effects.includes(rule.effect.type) ?? false;
              return (
                <View key={rule.id} style={{ gap: 4 }}>
                  <Toggle
                    label={`${rule.id}: ${rule.effect.type} · ${rule.trigger.offsetSeconds}s before ${rule.trigger.collectionId}.${rule.trigger.fieldId}`}
                    value={rules.includes(rule.id)}
                    disabled={locked || !supported}
                    onChange={(value) => {
                      setRules(
                        value
                          ? [...rules, rule.id]
                          : rules.filter((id) => id !== rule.id),
                      );
                      setApproved(false);
                    }}
                  />
                  {!supported && (
                    <Text style={styles.muted}>
                      This effect is not operational on this backend; publish
                      with it off.
                    </Text>
                  )}
                </View>
              );
            })
          )}
          <Field
            label="Existing live record IDs to enroll (optional)"
            hint="Enter exact current app record IDs, separated by spaces or commas. Leave blank to avoid enrolling existing records. The server checks every ID. Sample records are never included."
            multiline
            value={records}
            editable={!locked && rules.length > 0}
            onChangeText={(value) => {
              setRecords(value);
              setApproved(false);
            }}
          />
          <Button
            label="Prepare exact publication review"
            disabled={locked || !spec}
            busy={state.busy}
            onPress={() => {
              setApproved(false);
              void controller.review(rules, recordIds);
            }}
          />
        </>
      )}
      {review && (
        <View style={styles.card}>
          <Text accessibilityRole="header" style={styles.title}>
            Confirm this publication
          </Text>
          <Text style={styles.muted}>
            This review covers your saved candidate and the reminder selections
            below. Publishing makes this version available to people with access
            to the app.
          </Text>
          {review.changes.map((change, index) => (
            <Text key={index} style={styles.body}>
              • {change}
            </Text>
          ))}
          <Text style={styles.body}>
            Enabled rules: {review.enabledRuleIds.join(", ") || "None"}
          </Text>
          <Text style={styles.body}>
            Existing records to enroll:{" "}
            {review.activateExistingRecordIds.join(", ") || "None"}
          </Text>
          {review.compatibilityErrors.map((error, index) => (
            <Notice key={index} text={error} error />
          ))}
          <Toggle
            label="I reviewed this exact candidate and reminder scope"
            value={approved}
            disabled={
              locked || !scopeMatches || review.compatibilityErrors.length > 0
            }
            onChange={setApproved}
          />
          <Button
            label="Publish reviewed version"
            disabled={
              locked ||
              !approved ||
              !scopeMatches ||
              review.compatibilityErrors.length > 0
            }
            onPress={() => {
              void controller.publish();
            }}
          />
        </View>
      )}
    </Card>
  );
}
