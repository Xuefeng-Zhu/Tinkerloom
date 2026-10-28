import React, { useState } from "react";
import {
  Pressable,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from "react-native";
import { colors, space } from "../components/theme";
import {
  Definition,
  emptyValues,
  PreviewRecord,
  Values,
  validateValues,
} from "./model";
import { ModalFrame, PreviewButton, styles as shared } from "./ui";

export function PreviewForm({
  definition,
  record,
  onSave,
  onClose,
}: {
  definition: Definition;
  record?: PreviewRecord;
  onSave: (values: Values) => void;
  onClose: () => void;
}) {
  const [values, setValues] = useState<Values>(() =>
    record ? { ...record.values } : emptyValues(definition),
  );
  const [error, setError] = useState("");
  const setValue = (id: string, value: string | boolean) =>
    setValues((previous) => ({ ...previous, [id]: value }));

  function save() {
    try {
      onSave(validateValues(definition, values));
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "Please review the fields.",
      );
    }
  }

  return (
    <ModalFrame
      title={record ? "Edit sample record" : "Add sample record"}
      onClose={onClose}
    >
      <Text style={styles.hint}>Changes stay in this local preview.</Text>
      {definition.fields.map((field) => (
        <View key={field.id}>
          <Text style={shared.label}>
            {field.label}
            {field.required ? " *" : ""}
          </Text>
          {field.kind === "boolean" ? (
            <Switch
              accessibilityLabel={field.label}
              value={values[field.id] === true}
              onValueChange={(value) => setValue(field.id, value)}
              trackColor={{ true: colors.ink, false: colors.border }}
            />
          ) : field.kind === "choice" ? (
            <View
              accessibilityRole="radiogroup"
              accessibilityLabel={field.label}
              style={styles.options}
            >
              {!field.required && (
                <Choice
                  label="None"
                  selected={!values[field.id]}
                  onPress={() => setValue(field.id, "")}
                />
              )}
              {field.options?.map((option) => (
                <Choice
                  key={option}
                  label={option}
                  selected={values[field.id] === option}
                  onPress={() => setValue(field.id, option)}
                />
              ))}
            </View>
          ) : (
            <TextInput
              accessibilityLabel={field.label}
              value={String(values[field.id] ?? "")}
              onChangeText={(value) => setValue(field.id, value)}
              multiline={field.kind === "longText"}
              maxLength={field.kind === "longText" ? 4000 : 200}
              style={[
                shared.input,
                field.kind === "longText" && styles.longText,
              ]}
            />
          )}
        </View>
      ))}
      {error ? (
        <Text accessibilityRole="alert" style={shared.error}>
          {error}
        </Text>
      ) : null}
      <View style={shared.actions}>
        <PreviewButton label="Cancel" quiet onPress={onClose} />
        <PreviewButton label="Save sample" onPress={save} />
      </View>
    </ModalFrame>
  );
}

function Choice({
  label,
  selected,
  onPress,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      accessibilityRole="radio"
      accessibilityState={{ checked: selected }}
      onPress={onPress}
      style={({ pressed }) => [
        styles.choice,
        selected && styles.selectedChoice,
        pressed && shared.pressed,
      ]}
    >
      <Text style={[styles.choiceText, selected && styles.selectedText]}>
        {label}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  hint: { color: colors.muted, fontSize: 14, lineHeight: 21 },
  longText: { minHeight: 120, textAlignVertical: "top" },
  options: { flexDirection: "row", flexWrap: "wrap", gap: space.sm },
  choice: {
    minHeight: 44,
    paddingHorizontal: 12,
    paddingVertical: 12,
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 8,
    justifyContent: "center",
  },
  selectedChoice: { borderColor: colors.ink, backgroundColor: colors.sage },
  choiceText: { color: colors.muted, fontSize: 14 },
  selectedText: { color: colors.ink, fontWeight: "600" },
});
