import React from "react";
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from "react-native";
import { colors, space } from "../components/theme";
import { previewTemplates } from "./catalog";
import { PreviewTemplate } from "./model";
import { headingFont } from "./ui";

export function TemplateGallery({
  onClose,
  onSelect,
}: {
  onClose?: () => void;
  onSelect: (template: PreviewTemplate) => void;
}) {
  const { width } = useWindowDimensions();

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.topline}>
        <Text style={styles.wordmark}>Tinkerloom</Text>
        {onClose ? (
          <Pressable
            accessibilityRole="button"
            onPress={onClose}
            style={styles.back}
          >
            <Text style={styles.backText}>← Back</Text>
          </Pressable>
        ) : null}
      </View>
      <View style={styles.intro}>
        <Text style={styles.eyebrow}>THE SAMPLE SHELF</Text>
        <Text accessibilityRole="header" style={styles.title}>
          Start with a little{width >= 700 ? "\n" : " "}possibility.
        </Text>
        <Text style={styles.description}>
          Open a sample app, add a thought, or make its labels your own. A small
          taste of what you can weave together.
        </Text>
      </View>
      <View style={styles.notice}>
        <Text style={styles.noticeText}>
          Local previews use sample data in memory. They do not create apps or
          records in your Appwrite account.
        </Text>
      </View>
      <View style={styles.shelf}>
        {previewTemplates.map((template, index) => (
          <Pressable
            key={template.id}
            accessibilityRole="button"
            accessibilityLabel={`Preview ${template.definition.title}`}
            onPress={() => onSelect(template)}
            style={({ pressed }) => [
              styles.tile,
              width >= 850 && styles.wideTile,
              pressed && styles.pressed,
            ]}
          >
            <View style={styles.tileTop}>
              <Text style={styles.number}>0{index + 1}</Text>
              <Text style={styles.arrow}>↗</Text>
            </View>
            <View style={styles.paperLines}>
              <View style={[styles.paperLine, styles.shortLine]} />
              <View style={styles.paperLine} />
              <View style={[styles.paperLine, styles.mediumLine]} />
            </View>
            <Text style={styles.category}>{template.id.toUpperCase()}</Text>
            <Text accessibilityRole="header" style={styles.tileTitle}>
              {template.definition.title}
            </Text>
            <Text style={styles.caption}>{template.caption}</Text>
            <Text style={styles.open}>Open preview →</Text>
          </Pressable>
        ))}
      </View>
      <Text style={styles.footer}>
        Take a look around. Your workspaces stay separate, and every preview
        starts fresh.
      </Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.canvas },
  content: {
    width: "100%",
    maxWidth: 1120,
    alignSelf: "center",
    padding: space.lg,
    paddingBottom: space.xxl,
    gap: space.lg,
  },
  topline: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    gap: space.md,
  },
  wordmark: { fontFamily: headingFont, fontSize: 26, color: colors.ink },
  back: { minHeight: 44, justifyContent: "center" },
  backText: { color: colors.ink, fontSize: 15, fontWeight: "600" },
  intro: { paddingTop: space.lg, gap: space.md, maxWidth: 700 },
  eyebrow: {
    color: colors.accent,
    fontWeight: "700",
    letterSpacing: 2,
    fontSize: 11,
  },
  title: {
    fontFamily: headingFont,
    color: colors.ink,
    fontSize: 44,
    lineHeight: 52,
  },
  description: {
    color: colors.muted,
    fontSize: 17,
    lineHeight: 27,
    maxWidth: 580,
  },
  notice: { backgroundColor: colors.sage, borderRadius: 8, padding: space.md },
  noticeText: { color: colors.ink, fontSize: 14, lineHeight: 22 },
  shelf: { flexDirection: "row", flexWrap: "wrap", gap: space.md },
  tile: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: space.lg,
    gap: space.md,
    width: "100%",
  },
  wideTile: { flex: 1, minWidth: 240, width: undefined },
  pressed: { opacity: 0.7 },
  tileTop: { flexDirection: "row", justifyContent: "space-between" },
  number: { color: colors.muted, fontSize: 12, letterSpacing: 1 },
  arrow: { color: colors.accent, fontSize: 23, lineHeight: 24 },
  paperLines: {
    backgroundColor: colors.canvas,
    borderRadius: 6,
    padding: space.lg,
    gap: 10,
    marginVertical: space.sm,
  },
  paperLine: {
    backgroundColor: colors.border,
    height: 5,
    width: "100%",
    borderRadius: 4,
  },
  shortLine: { width: "40%", backgroundColor: colors.accent },
  mediumLine: { width: "75%" },
  category: {
    color: colors.accent,
    letterSpacing: 1.5,
    fontWeight: "600",
    fontSize: 10,
  },
  tileTitle: {
    fontFamily: headingFont,
    color: colors.ink,
    fontSize: 25,
    lineHeight: 32,
  },
  caption: { color: colors.muted, fontSize: 15, lineHeight: 24, flex: 1 },
  open: {
    color: colors.ink,
    fontSize: 14,
    fontWeight: "600",
    marginTop: space.sm,
  },
  footer: { color: colors.muted, fontSize: 13, lineHeight: 21, maxWidth: 680 },
});
