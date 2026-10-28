import { ActivityIndicator, Pressable, StyleSheet, Text } from "react-native";
import { colors, space } from "./theme";

interface ButtonProps {
  label: string;
  onPress: () => void;
  variant?: "primary" | "secondary" | "quiet";
  disabled?: boolean;
  busy?: boolean;
  accessibilityLabel?: string;
}

export function Button({
  label,
  onPress,
  variant = "primary",
  disabled = false,
  busy = false,
  accessibilityLabel,
}: ButtonProps) {
  const inactive = disabled || busy;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? label}
      accessibilityState={{ disabled: inactive, busy }}
      disabled={inactive}
      onPress={onPress}
      style={({ pressed }) => [
        styles.base,
        styles[variant],
        inactive && styles.disabled,
        pressed && styles.pressed,
      ]}
    >
      {busy && (
        <ActivityIndicator
          color={variant === "primary" ? colors.surface : colors.ink}
        />
      )}
      <Text
        style={[styles.label, variant === "primary" && styles.primaryLabel]}
      >
        {label}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: {
    minHeight: 48,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    borderRadius: 10,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: space.sm,
    borderWidth: 1,
  },
  primary: { backgroundColor: colors.ink, borderColor: colors.ink },
  secondary: { backgroundColor: colors.surface, borderColor: colors.border },
  quiet: { backgroundColor: "transparent", borderColor: "transparent" },
  label: {
    color: colors.ink,
    fontSize: 15,
    fontWeight: "600",
    flexShrink: 1,
    textAlign: "center",
  },
  primaryLabel: { color: colors.surface },
  disabled: { opacity: 0.55 },
  pressed: { opacity: 0.8 },
});
