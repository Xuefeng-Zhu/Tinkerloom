import { useState } from "react";
import { Pressable, StyleSheet, Switch, Text, View } from "react-native";
import type { LiveRecord } from "../backend/types";
import { Button } from "../components/Button";
import { Field } from "../components/Field";
import { Notice } from "../components/Notice";
import { colors, space } from "../components/theme";
import { emptyValues } from "../preview/model";
import type { Definition, Values } from "../preview/model";
import { ModalFrame } from "../preview/ui";
import { savePresentation } from "./saveStatus";
import { prepareRecordValues, recordInputHint } from "./recordInputs";

export function RecordEditor({
  definition,
  record,
  busy,
  locked,
  error,
  onSave,
  onClose,
}: {
  definition: Definition;
  record: LiveRecord | null;
  busy: boolean;
  locked: boolean;
  error: string | null;
  onSave: (values: Values) => void;
  onClose: () => void;
}) {
  const [values, setValues] = useState<Values>(() =>
    record ? { ...record.values } : emptyValues(definition),
  );
  const [validation, setValidation] = useState<string | null>(null);
  const inactive = busy || locked;
  const saveStatus = savePresentation(busy || locked ? "record" : null, busy);
  const update = (id: string, value: string | boolean) =>
    setValues((old) => ({ ...old, [id]: value }));
  function save() {
    if (inactive) return;
    try {
      const valid = prepareRecordValues(definition, values);
      setValidation(null);
      onSave(valid);
    } catch (error) {
      setValidation(
        error instanceof Error ? error.message : "Please review the fields.",
      );
    }
  }
  return (
    <ModalFrame
      title={record ? "Edit record" : "New record"}
      onClose={() => {
        if (!busy) onClose();
      }}
    >
      <Text style={styles.hint}>
        Saved records belong to this published app.
      </Text>
      {definition.fields.map((field) => (
        <View key={field.id} style={styles.group}>
          {field.kind === "boolean" ? (
            <>
              <Text style={styles.label}>{field.label}</Text>
              <Switch
                accessibilityLabel={field.label}
                value={values[field.id] === true}
                disabled={inactive}
                onValueChange={(value) => update(field.id, value)}
              />
            </>
          ) : field.kind === "choice" ? (
            <>
              <Text style={styles.label}>
                {field.label}
                {field.required ? " *" : ""}
              </Text>
              <View
                accessibilityRole="radiogroup"
                accessibilityLabel={field.label}
                style={styles.choices}
              >
                {[
                  ...(field.required ? [] : [""]),
                  ...(field.options ?? []),
                ].map((option) => (
                  <Pressable
                    key={option}
                    accessibilityRole="radio"
                    accessibilityState={{
                      checked: values[field.id] === option,
                      disabled: inactive,
                    }}
                    disabled={inactive}
                    onPress={() => update(field.id, option)}
                    style={[
                      styles.choice,
                      values[field.id] === option && styles.selected,
                    ]}
                  >
                    <Text style={styles.choiceText}>{option || "None"}</Text>
                  </Pressable>
                ))}
              </View>
            </>
          ) : (
            <Field
              label={field.label}
              hint={recordInputHint(field.kind, field.required)}
              value={String(values[field.id] ?? "")}
              editable={!inactive}
              onChangeText={(value) => update(field.id, value)}
              maxLength={field.kind === "longText" ? 4000 : 200}
              multiline={field.kind === "longText"}
              autoCapitalize={
                field.kind === "date" || field.kind === "number"
                  ? "none"
                  : "sentences"
              }
              autoCorrect={field.kind !== "date" && field.kind !== "number"}
              style={field.kind === "longText" ? styles.longText : undefined}
            />
          )}
        </View>
      ))}
      {(validation || error) && <Notice error text={validation ?? error!} />}
      {saveStatus && (
        <Text accessibilityLiveRegion="polite" style={styles.hint}>
          {saveStatus.title}
          {!busy
            ? ". Close the editor to review and retry the same save above the record list."
            : ""}
        </Text>
      )}
      <Button
        label={busy ? "Saving record…" : "Save record"}
        onPress={save}
        busy={busy}
        disabled={locked}
      />
      <Button label="Close" variant="quiet" onPress={onClose} disabled={busy} />
    </ModalFrame>
  );
}

const styles = StyleSheet.create({
  group: { gap: space.sm },
  label: { color: colors.ink, fontSize: 14, fontWeight: "600" },
  hint: { color: colors.muted, fontSize: 14, lineHeight: 21 },
  choices: { flexDirection: "row", flexWrap: "wrap", gap: space.sm },
  choice: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    minHeight: 44,
    justifyContent: "center",
    padding: 12,
  },
  selected: { backgroundColor: colors.sage, borderColor: colors.ink },
  choiceText: { color: colors.ink, fontSize: 14 },
  longText: { minHeight: 120, textAlignVertical: "top" },
});
