import {
  StyleSheet,
  Text,
  TextInput,
  TextInputProps,
  View,
} from "react-native";
import { colors, space } from "./theme";

interface FieldProps extends TextInputProps {
  label: string;
  hint?: string;
}

export function Field({ label, hint, style, ...props }: FieldProps) {
  return (
    <View style={styles.group}>
      <Text style={styles.label}>{label}</Text>
      <TextInput
        accessibilityLabel={label}
        placeholderTextColor={colors.muted}
        {...props}
        style={[
          styles.input,
          props.editable === false && styles.readOnly,
          style,
        ]}
      />
      {hint && <Text style={styles.hint}>{hint}</Text>}
    </View>
  );
}

const styles = StyleSheet.create({
  group: { gap: space.sm },
  label: { color: colors.ink, fontSize: 14, fontWeight: "600" },
  input: {
    minHeight: 50,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 10,
    paddingHorizontal: space.md,
    paddingVertical: 12,
    backgroundColor: colors.surface,
    color: colors.ink,
    fontSize: 16,
  },
  readOnly: { backgroundColor: colors.canvas },
  hint: { color: colors.muted, fontSize: 13, lineHeight: 19 },
});
