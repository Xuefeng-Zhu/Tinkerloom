import type { ReactNode } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { colors, space } from "../components/theme";
export const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.canvas },
  content: {
    width: "100%",
    maxWidth: 1080,
    alignSelf: "center",
    padding: space.lg,
    gap: space.md,
    paddingBottom: 64,
  },
  row: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: space.sm,
    alignItems: "center",
  },
  card: {
    padding: space.md,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surface,
    gap: space.md,
  },
  heading: {
    fontSize: 28,
    lineHeight: 34,
    fontWeight: "700",
    color: colors.ink,
  },
  title: { fontSize: 20, lineHeight: 27, fontWeight: "600", color: colors.ink },
  body: { fontSize: 15, lineHeight: 23, color: colors.ink },
  muted: { fontSize: 13, lineHeight: 20, color: colors.muted },
  label: {
    fontSize: 12,
    fontWeight: "700",
    letterSpacing: 1.1,
    color: colors.accent,
    textTransform: "uppercase",
  },
  choice: {
    minHeight: 44,
    paddingHorizontal: 13,
    paddingVertical: 11,
    borderRadius: 9,
    borderWidth: 1,
    borderColor: colors.border,
    justifyContent: "center",
    backgroundColor: colors.surface,
  },
  chosen: { backgroundColor: colors.sage, borderColor: colors.ink },
  grow: { flexGrow: 1, flexBasis: 260 },
  divider: { height: 1, backgroundColor: colors.border },
});
export function Card({
  title,
  children,
}: {
  title?: string;
  children: ReactNode;
}) {
  return (
    <View style={styles.card}>
      {title && (
        <Text accessibilityRole="header" style={styles.title}>
          {title}
        </Text>
      )}
      {children}
    </View>
  );
}
export function Choices<T extends string>({
  label,
  values,
  value,
  onChange,
  disabled = false,
}: {
  label: string;
  values: readonly T[];
  value: T;
  onChange: (value: T) => void;
  disabled?: boolean;
}) {
  return (
    <View style={{ gap: 8 }}>
      <Text style={styles.muted}>{label}</Text>
      <View accessibilityRole="radiogroup" style={styles.row}>
        {values.map((item) => (
          <Pressable
            key={item}
            accessibilityRole="radio"
            accessibilityLabel={`${label}: ${item}`}
            accessibilityState={{ checked: item === value, disabled }}
            disabled={disabled}
            onPress={() => onChange(item)}
            style={[
              styles.choice,
              item === value && styles.chosen,
              disabled && { opacity: 0.5 },
            ]}
          >
            <Text style={styles.body}>{item}</Text>
          </Pressable>
        ))}
      </View>
    </View>
  );
}
export function Toggle({
  label,
  value,
  onChange,
  disabled = false,
}: {
  label: string;
  value: boolean;
  onChange: (value: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="checkbox"
      accessibilityLabel={label}
      accessibilityState={{ checked: value, disabled }}
      disabled={disabled}
      onPress={() => onChange(!value)}
      style={[styles.choice, value && styles.chosen]}
    >
      <Text style={styles.body}>
        {value ? "✓ " : "○ "}
        {label}
      </Text>
    </Pressable>
  );
}
