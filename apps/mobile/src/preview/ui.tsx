import React from "react";
import {
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { colors, space } from "../components/theme";

export const headingFont = Platform.select({
  ios: "Georgia",
  web: "Georgia",
  default: "serif",
});

export function PreviewButton({
  label,
  onPress,
  quiet = false,
}: {
  label: string;
  onPress: () => void;
  quiet?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        quiet ? styles.quiet : styles.primary,
        pressed && styles.pressed,
      ]}
    >
      <Text style={[styles.buttonText, quiet && styles.quietText]}>
        {label}
      </Text>
    </Pressable>
  );
}

export function ModalFrame({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
}) {
  return (
    <Modal transparent animationType="fade" onRequestClose={onClose}>
      <KeyboardAvoidingView
        behavior={
          Platform.OS === "ios"
            ? "padding"
            : Platform.OS === "android"
              ? "height"
              : undefined
        }
        style={styles.backdrop}
      >
        <View style={styles.dialog} accessibilityViewIsModal>
          <View style={styles.dialogHeader}>
            <Text accessibilityRole="header" style={styles.dialogTitle}>
              {title}
            </Text>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Close editor"
              onPress={onClose}
              hitSlop={12}
              style={styles.close}
            >
              <Text style={styles.closeText}>×</Text>
            </Pressable>
          </View>
          <ScrollView
            keyboardShouldPersistTaps="handled"
            contentContainerStyle={styles.dialogContent}
          >
            {children}
          </ScrollView>
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}

export const styles = StyleSheet.create({
  button: {
    minHeight: 48,
    paddingHorizontal: space.md,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: 1,
  },
  primary: { backgroundColor: colors.ink, borderColor: colors.ink },
  quiet: { backgroundColor: colors.surface, borderColor: colors.border },
  buttonText: { fontSize: 15, fontWeight: "600", color: colors.surface },
  quietText: { color: colors.ink },
  pressed: { opacity: 0.72 },
  backdrop: {
    flex: 1,
    backgroundColor: "rgba(25, 39, 30, 0.4)",
    justifyContent: "center",
    padding: space.md,
  },
  dialog: {
    width: "100%",
    maxWidth: 520,
    maxHeight: "90%",
    alignSelf: "center",
    backgroundColor: colors.canvas,
    borderRadius: 16,
    overflow: "hidden",
  },
  dialogHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    padding: space.lg,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
    gap: space.md,
  },
  dialogTitle: {
    fontSize: 26,
    fontFamily: headingFont,
    color: colors.ink,
    flex: 1,
  },
  close: {
    minWidth: 44,
    minHeight: 44,
    justifyContent: "center",
    alignItems: "center",
  },
  closeText: { color: colors.ink, fontSize: 30 },
  dialogContent: { padding: space.lg, gap: space.md },
  label: {
    color: colors.ink,
    fontSize: 14,
    fontWeight: "600",
    marginBottom: space.sm,
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    backgroundColor: colors.surface,
    color: colors.ink,
    padding: 12,
    minHeight: 48,
    fontSize: 16,
  },
  error: { color: colors.danger, fontSize: 14, lineHeight: 21 },
  actions: {
    flexDirection: "row",
    justifyContent: "flex-end",
    gap: space.sm,
    flexWrap: "wrap",
    marginTop: space.sm,
  },
});
