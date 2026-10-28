import { useState } from "react";
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { Brand } from "../components/Brand";
import { Button } from "../components/Button";
import { Field } from "../components/Field";
import { Notice } from "../components/Notice";
import { colors, space } from "../components/theme";

export interface AuthScreenProps {
  busy: boolean;
  error: string | null;
  onSignIn: (email: string, password: string) => void | Promise<void>;
  onSignUp: (
    email: string,
    password: string,
    name: string,
  ) => void | Promise<void>;
  onPreview: () => void;
  onRestoreSession: () => void;
}

export function AuthScreen({
  busy,
  error,
  onSignIn,
  onSignUp,
  onPreview,
  onRestoreSession,
}: AuthScreenProps) {
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [validation, setValidation] = useState<string | null>(null);

  function submit() {
    const address = email.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)) {
      setValidation("Enter a valid email address.");
      return;
    }
    if (!password || (mode === "signup" && password.length < 8)) {
      setValidation(
        mode === "signup"
          ? "Use a password with at least 8 characters."
          : "Enter your password.",
      );
      return;
    }
    if (mode === "signup" && (!name.trim() || name.trim().length > 128)) {
      setValidation("Enter your name using up to 128 characters.");
      return;
    }
    setValidation(null);
    if (mode === "signup") void onSignUp(address, password, name.trim());
    else void onSignIn(address, password);
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
        <View style={styles.frame}>
          <Brand />
          <View style={styles.intro}>
            <Text style={styles.eyebrow}>
              A LITTLE STRUCTURE. MORE POSSIBILITY.
            </Text>
            <Text style={styles.heading} accessibilityRole="header">
              Small tools, woven{"\n"}around your life.
            </Text>
            <Text style={styles.description}>
              A place for everyday ideas to become useful little apps.
            </Text>
          </View>
          <View style={styles.form}>
            <View style={styles.tabs}>
              {(["signin", "signup"] as const).map((value) => (
                <Pressable
                  key={value}
                  accessibilityRole="tab"
                  accessibilityState={{
                    selected: mode === value,
                    disabled: busy,
                  }}
                  disabled={busy}
                  onPress={() => {
                    setMode(value);
                    setValidation(null);
                  }}
                  style={[styles.tab, mode === value && styles.activeTab]}
                >
                  <Text
                    style={[
                      styles.tabText,
                      mode === value && styles.activeTabText,
                    ]}
                  >
                    {value === "signin" ? "Sign in" : "Create account"}
                  </Text>
                </Pressable>
              ))}
            </View>
            <Text style={styles.formTitle} accessibilityRole="header">
              {mode === "signin" ? "Welcome back" : "Make room for your ideas"}
            </Text>
            {mode === "signup" && (
              <Field
                label="Your name"
                value={name}
                onChangeText={setName}
                editable={!busy}
                autoComplete="name"
                textContentType="name"
                maxLength={128}
              />
            )}
            <Field
              label="Email"
              value={email}
              onChangeText={setEmail}
              editable={!busy}
              keyboardType="email-address"
              autoCapitalize="none"
              autoCorrect={false}
              autoComplete="email"
              textContentType="emailAddress"
              returnKeyType="next"
            />
            <Field
              label="Password"
              value={password}
              onChangeText={setPassword}
              editable={!busy}
              secureTextEntry
              autoCapitalize="none"
              autoCorrect={false}
              autoComplete={
                mode === "signin" ? "current-password" : "new-password"
              }
              textContentType={mode === "signin" ? "password" : "newPassword"}
              returnKeyType="go"
              onSubmitEditing={submit}
              hint={mode === "signup" ? "At least 8 characters." : undefined}
            />
            {(validation || error) && (
              <Notice text={validation ?? error!} error />
            )}
            <Button
              label={
                busy
                  ? "Please wait…"
                  : mode === "signin"
                    ? "Sign in"
                    : "Create account"
              }
              onPress={submit}
              busy={busy}
            />
            <Button
              label="Check existing session"
              variant="quiet"
              onPress={onRestoreSession}
              disabled={busy}
            />
          </View>
          <View style={styles.preview}>
            <Text style={styles.previewTitle}>
              Start with a little inspiration
            </Text>
            <Text style={styles.previewText}>
              Try a template with sample data before signing in.
            </Text>
            <Button
              label="Explore templates"
              variant="secondary"
              onPress={onPreview}
              disabled={busy}
            />
          </View>
          <Text style={styles.footer}>A place for everyday ideas.</Text>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.canvas },
  scroll: { flexGrow: 1, padding: space.lg, alignItems: "center" },
  frame: {
    width: "100%",
    maxWidth: 500,
    gap: space.lg,
    paddingVertical: space.lg,
  },
  intro: { gap: space.md, paddingVertical: space.sm },
  eyebrow: {
    color: colors.accent,
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 1.1,
    lineHeight: 17,
  },
  heading: {
    color: colors.ink,
    fontSize: 38,
    lineHeight: 43,
    fontWeight: "700",
    letterSpacing: -1.4,
  },
  description: {
    color: colors.muted,
    fontSize: 17,
    lineHeight: 25,
    maxWidth: 380,
  },
  form: {
    backgroundColor: colors.surface,
    padding: space.lg,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 16,
    gap: space.md,
  },
  tabs: {
    flexDirection: "row",
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
    marginBottom: space.sm,
  },
  tab: {
    flex: 1,
    minHeight: 48,
    justifyContent: "center",
    alignItems: "center",
    borderBottomWidth: 2,
    borderBottomColor: "transparent",
    paddingHorizontal: space.sm,
  },
  activeTab: { borderBottomColor: colors.accent },
  tabText: {
    color: colors.muted,
    fontSize: 14,
    fontWeight: "600",
    textAlign: "center",
  },
  activeTabText: { color: colors.ink },
  formTitle: {
    color: colors.ink,
    fontSize: 21,
    lineHeight: 28,
    fontWeight: "600",
  },
  preview: { gap: space.sm },
  previewTitle: { color: colors.ink, fontWeight: "600", fontSize: 16 },
  previewText: {
    color: colors.muted,
    fontSize: 14,
    lineHeight: 21,
    marginBottom: space.sm,
  },
  footer: { color: colors.muted, fontSize: 12, textAlign: "center" },
});
