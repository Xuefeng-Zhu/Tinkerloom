import { StyleSheet, Text, View } from "react-native";
import { colors, space } from "./theme";

export function Notice({
  text,
  error = false,
}: {
  text: string;
  error?: boolean;
}) {
  return (
    <View
      style={[styles.container, error && styles.error]}
      accessibilityRole={error ? "alert" : undefined}
    >
      <Text style={[styles.text, error && styles.errorText]} selectable>
        {text}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderRadius: 10,
    padding: space.md,
    backgroundColor: colors.sage,
  },
  error: { backgroundColor: "#FCECEA" },
  text: { color: colors.ink, fontSize: 14, lineHeight: 21 },
  errorText: { color: colors.danger },
});
