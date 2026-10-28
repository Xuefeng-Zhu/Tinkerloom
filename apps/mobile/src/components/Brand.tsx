import { StyleSheet, Text, View } from "react-native";
import { colors, space } from "./theme";

export function Brand() {
  return (
    <View style={styles.brand}>
      <View
        style={styles.mark}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <View style={[styles.thread, styles.horizontalTop]} />
        <View style={[styles.thread, styles.horizontalBottom]} />
        <View style={[styles.thread, styles.verticalLeft]} />
        <View style={[styles.thread, styles.verticalRight]} />
      </View>
      <Text style={styles.name}>tinkerloom</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  brand: { flexDirection: "row", alignItems: "center", gap: space.sm },
  mark: {
    width: 30,
    height: 30,
    backgroundColor: colors.accentSoft,
    borderRadius: 7,
  },
  thread: {
    position: "absolute",
    backgroundColor: colors.accent,
    borderRadius: 2,
  },
  horizontalTop: { left: 5, right: 5, top: 9, height: 3 },
  horizontalBottom: { left: 5, right: 5, top: 18, height: 3 },
  verticalLeft: { top: 5, bottom: 5, left: 9, width: 3 },
  verticalRight: { top: 5, bottom: 5, left: 18, width: 3 },
  name: {
    color: colors.ink,
    fontSize: 23,
    fontWeight: "700",
    letterSpacing: -0.8,
  },
});
