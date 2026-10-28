import React, { useState } from "react";
import { Text, TextInput, View } from "react-native";
import {
  PreviewSession,
  customizePreview,
  Definition,
  validateDefinition,
} from "./model";
import { RecordViewPicker } from "../live/RecordViewPicker";
import { ModalFrame, PreviewButton, styles } from "./ui";

export function CustomizeForm({
  session,
  onSave,
  onClose,
}: {
  session: PreviewSession;
  onSave: (session: PreviewSession) => void;
  onClose: () => void;
}) {
  const [title, setTitle] = useState(session.definition.title);
  const [labels, setLabels] = useState<Record<string, string>>(() =>
    Object.fromEntries(
      session.definition.fields.map((field) => [field.id, field.label]),
    ),
  );
  const [error, setError] = useState("");
  const [view, setView] = useState<Definition["view"]>(session.definition.view);

  function save() {
    try {
      const next = customizePreview(session, title, labels);
      if (view !== undefined) next.definition = { ...next.definition, view };
      validateDefinition(next.definition);
      onSave(next);
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "Please review the labels.",
      );
    }
  }

  return (
    <ModalFrame title="Make it your own" onClose={onClose}>
      <View>
        <Text style={styles.label}>App title</Text>
        <TextInput
          accessibilityLabel="App title"
          value={title}
          onChangeText={setTitle}
          maxLength={80}
          style={styles.input}
        />
      </View>
      {session.definition.fields.map((field) => (
        <View key={field.id}>
          <Text style={styles.label}>{field.label} label</Text>
          <TextInput
            accessibilityLabel={`${field.label} label`}
            value={labels[field.id]}
            onChangeText={(label) =>
              setLabels((previous) => ({ ...previous, [field.id]: label }))
            }
            maxLength={64}
            style={styles.input}
          />
        </View>
      ))}
      <RecordViewPicker
        definition={{
          ...session.definition,
          ...(view === undefined ? {} : { view }),
        }}
        onChange={setView}
      />
      {error ? (
        <Text accessibilityRole="alert" style={styles.error}>
          {error}
        </Text>
      ) : null}
      <View style={styles.actions}>
        <PreviewButton label="Cancel" quiet onPress={onClose} />
        <PreviewButton label="Apply to preview" onPress={save} />
      </View>
    </ModalFrame>
  );
}
