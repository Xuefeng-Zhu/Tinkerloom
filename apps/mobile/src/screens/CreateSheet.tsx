import { useState } from "react";
import {
  KeyboardAvoidingView,
  Modal,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { Button } from "../components/Button";
import { Field } from "../components/Field";
import { Notice } from "../components/Notice";
import { colors, space } from "../components/theme";

export interface CreateSheetProps {
  kind: "workspace" | "app";
  busy: boolean;
  error: string | null;
  submittedName?: string;
  workspaceName?: string;
  onSubmit: (name: string) => void;
  onCancel: () => void;
}

export function CreateSheet({
  kind,
  busy,
  error,
  submittedName,
  workspaceName,
  onSubmit,
  onCancel,
}: CreateSheetProps) {
  const [name, setName] = useState("");
  const [validation, setValidation] = useState<string | null>(null);
  const locked = submittedName !== undefined;
  const title = kind === "workspace" ? "New workspace" : "New app";

  function submit() {
    if (busy) return;
    const value = submittedName ?? name.trim();
    if (!value || value.length > 128) {
      setValidation("Choose a name using 1–128 characters.");
      return;
    }
    setValidation(null);
    onSubmit(value);
  }

  return (
    <Modal
      visible
      transparent
      animationType="fade"
      onRequestClose={() => {
        if (!busy) onCancel();
      }}
    >
      <KeyboardAvoidingView
        style={styles.overlay}
        behavior={Platform.OS === "ios" ? "padding" : undefined}
      >
        <View style={styles.sheet} accessibilityViewIsModal>
          <ScrollView
            contentContainerStyle={styles.content}
            keyboardShouldPersistTaps="handled"
          >
            <Text style={styles.eyebrow}>MAKE A LITTLE SPACE</Text>
            <Text style={styles.title} accessibilityRole="header">
              {title}
            </Text>
            <Text style={styles.description}>
              {kind === "workspace"
                ? "Keep a collection of useful little tools together."
                : "Choose a name, then open the app to pick a template and make it your own."}
            </Text>
            {kind === "app" && (
              <Text style={styles.recovery}>
                Workspace: {workspaceName ?? "the original workspace"}
              </Text>
            )}
            <Field
              label={kind === "workspace" ? "Workspace name" : "App name"}
              value={submittedName ?? name}
              onChangeText={setName}
              editable={!busy && !locked}
              maxLength={128}
              autoFocus
              returnKeyType="done"
              onSubmitEditing={submit}
              placeholder={
                kind === "workspace" ? "Everyday things" : "A small idea"
              }
            />
            {(validation || error) && (
              <Notice text={validation ?? error!} error />
            )}
            {locked && (
              <Text style={styles.recovery}>
                This attempt keeps its original name and request ID. Retry save
                to safely check the same creation.
              </Text>
            )}
            <View style={styles.actions}>
              <Button
                label={busy ? "Saving…" : locked ? "Retry save" : "Create"}
                onPress={submit}
                busy={busy}
              />
              <Button
                label={locked ? "Close" : "Cancel"}
                variant="quiet"
                onPress={onCancel}
                disabled={busy}
              />
            </View>
            {locked && (
              <Text style={styles.footnote}>
                Closing does not undo a request that reached the server. Refresh
                the list before starting another creation.
              </Text>
            )}
          </ScrollView>
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: "rgba(24, 37, 29, 0.4)",
    justifyContent: "center",
    alignItems: "center",
    padding: space.md,
  },
  sheet: {
    width: "100%",
    maxWidth: 480,
    maxHeight: "92%",
    backgroundColor: colors.surface,
    borderRadius: 16,
  },
  content: { padding: space.lg, gap: space.md },
  eyebrow: {
    color: colors.accent,
    fontSize: 11,
    letterSpacing: 0.8,
    fontWeight: "700",
  },
  title: {
    color: colors.ink,
    fontSize: 27,
    lineHeight: 33,
    fontWeight: "600",
    letterSpacing: -0.5,
  },
  description: { color: colors.muted, fontSize: 15, lineHeight: 23 },
  recovery: { color: colors.ink, fontSize: 13, lineHeight: 20 },
  actions: { gap: space.sm, paddingTop: space.sm },
  footnote: { color: colors.muted, fontSize: 12, lineHeight: 19 },
});
