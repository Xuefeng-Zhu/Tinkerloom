import { useState } from "react";
import {
  KeyboardAvoidingView,
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
import { readInvitationToken } from "../sharing/invitationInput";

export function InvitationEntryScreen({
  onReview,
  onBack,
}: {
  onReview: (token: string) => void;
  onBack: () => void;
}) {
  const [input, setInput] = useState("");
  const [error, setError] = useState<string | null>(null);
  function review() {
    const token = readInvitationToken(input);
    if (!token) {
      setError("Paste a complete invitation link or its 43-character code.");
      return;
    }
    setError(null);
    onReview(token);
  }
  return (
    <KeyboardAvoidingView
      style={styles.root}
      behavior={Platform.OS === "ios" ? "padding" : undefined}
    >
      <ScrollView
        contentContainerStyle={styles.scroll}
        keyboardShouldPersistTaps="handled"
      >
        <View style={styles.content}>
          <Button label="← Workbench" variant="quiet" onPress={onBack} />
          <Text style={styles.eyebrow}>A SHARED LITTLE SPACE</Text>
          <Text accessibilityRole="header" style={styles.title}>
            Open an invitation
          </Text>
          <Text style={styles.description}>
            Have a link from someone? Paste it here to check the app and the
            role they are offering.
          </Text>
          <Field
            label="Invitation link or code"
            hint="Use the complete link, or the 43-character code at its end."
            value={input}
            onChangeText={(value) => {
              setInput(value);
              setError(null);
            }}
            autoCapitalize="none"
            autoCorrect={false}
            spellCheck={false}
            maxLength={2048}
            returnKeyType="go"
            onSubmitEditing={review}
          />
          {error && <Notice text={error} error />}
          <Button label="Review invitation" onPress={review} />
          <Text style={styles.hint}>
            You may need to sign in first. You will still review the invitation
            and choose Accept before any access is added.
          </Text>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.canvas },
  scroll: { flexGrow: 1, alignItems: "center", padding: space.lg },
  content: {
    width: "100%",
    maxWidth: 560,
    gap: space.lg,
    paddingBottom: space.xl,
  },
  eyebrow: {
    color: colors.accent,
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 1.1,
  },
  title: {
    color: colors.ink,
    fontSize: 32,
    lineHeight: 39,
    fontWeight: "700",
    letterSpacing: -0.7,
  },
  description: { color: colors.muted, fontSize: 16, lineHeight: 25 },
  hint: { color: colors.muted, fontSize: 13, lineHeight: 21 },
});
