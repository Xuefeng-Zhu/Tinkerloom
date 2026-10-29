import {
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
  Platform,
} from "react-native";
import type { ReactNode, Ref, ElementRef } from "react";
import type { TextInputProps, ViewStyle } from "react-native";
import { useRuntime } from "./context";
export function Body({
  children,
  muted = false,
  heading = false,
}: {
  children: ReactNode;
  muted?: boolean;
  heading?: boolean;
}) {
  const { theme } = useRuntime();
  return (
    <Text
      style={{
        color: muted ? theme.muted : theme.ink,
        fontSize: heading ? 22 : 16,
        lineHeight: heading ? 30 : 24,
        fontWeight: heading ? "600" : "400",
        ...(heading && theme.serif ? { fontFamily: "serif" } : {}),
      }}
      accessibilityRole={heading ? "header" : undefined}
    >
      {children}
    </Text>
  );
}
export function Panel({
  children,
  title,
  style,
}: {
  children: ReactNode;
  title?: string;
  style?: ViewStyle;
}) {
  const { theme } = useRuntime();
  return (
    <View
      style={[
        {
          backgroundColor: theme.surface,
          borderColor: theme.outline,
          borderWidth: 1,
          borderRadius: theme.radius,
          padding: 20 * theme.spacing,
          gap: 12 * theme.spacing,
          minWidth: 0,
        },
        style,
      ]}
    >
      {title ? <Body heading>{title}</Body> : null}
      {children}
    </View>
  );
}
export function Row({ children }: { children: ReactNode }) {
  return <View style={styles.row}>{children}</View>;
}
export function Button({
  children,
  onPress,
  disabled = false,
  selected = false,
  subtle = false,
  label,
  ref,
}: {
  children: ReactNode;
  onPress: () => void;
  disabled?: boolean;
  selected?: boolean;
  subtle?: boolean;
  label?: string;
  ref?: Ref<ElementRef<typeof Pressable>>;
}) {
  const { theme } = useRuntime();
  const filled = selected || !subtle;
  return (
    <Pressable
      ref={ref}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled, selected }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: 44,
        minWidth: 44,
        paddingHorizontal: 14,
        paddingVertical: 10,
        borderRadius: Math.min(theme.radius, 16),
        borderWidth: 1,
        borderColor: filled ? theme.accent : theme.outline,
        backgroundColor: filled ? theme.accent : theme.surface,
        opacity: disabled ? 0.45 : pressed ? 0.7 : 1,
        justifyContent: "center",
      })}
    >
      <Text
        style={{
          fontSize: 15,
          fontWeight: "600",
          color: filled ? theme.onAccent : theme.ink,
        }}
      >
        {children}
      </Text>
    </Pressable>
  );
}
export function Input({
  ref,
  invalid = false,
  errorId,
  ...props
}: TextInputProps & {
  ref?: Ref<ElementRef<typeof TextInput>>;
  invalid?: boolean;
  errorId?: string;
}) {
  const { theme } = useRuntime();
  // These verified RNWeb props are not forwarded to unsupported native hosts.
  const webValidation =
    Platform.OS === "web"
      ? {
          "aria-invalid": invalid,
          "aria-describedby": invalid ? errorId : undefined,
          "aria-errormessage": invalid ? errorId : undefined,
        }
      : {};
  return (
    <TextInput
      {...props}
      {...webValidation}
      ref={ref}
      placeholderTextColor={theme.muted}
      style={[
        {
          borderWidth: 1,
          borderColor: invalid ? "#b42318" : theme.outline,
          borderRadius: Math.min(theme.radius, 10),
          padding: 12,
          minHeight: 48,
          color: theme.ink,
          backgroundColor: theme.surface,
          fontSize: 16,
        },
        props.style,
      ]}
    />
  );
}
export function Notice({
  children,
  error = false,
}: {
  children: ReactNode;
  error?: boolean;
}) {
  const { theme } = useRuntime();
  return (
    <View
      style={{
        padding: 12,
        borderLeftWidth: 3,
        borderLeftColor: error ? "#b42318" : theme.accent,
        backgroundColor: error ? "#fff0ee" : theme.canvas,
      }}
    >
      <Text
        accessibilityRole={error ? "alert" : undefined}
        style={{
          fontSize: 15,
          lineHeight: 22,
          color: error ? "#8b1e16" : theme.ink,
        }}
      >
        {children}
      </Text>
    </View>
  );
}
const styles = StyleSheet.create({
  row: { flexDirection: "row", alignItems: "center", flexWrap: "wrap", gap: 8 },
});
