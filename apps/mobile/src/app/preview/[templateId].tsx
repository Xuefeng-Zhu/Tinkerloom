import { router, useLocalSearchParams } from "expo-router";
import { StyleSheet, Text, View } from "react-native";
import { Button } from "../../components/Button";
import { colors, space } from "../../components/theme";
import { previewTemplates } from "../../preview/catalog";
import { PreviewApp } from "../../preview/PreviewApp";

export default function TemplatePreviewRoute() {
  const { templateId } = useLocalSearchParams<{
    templateId?: string | string[];
  }>();
  const template =
    typeof templateId === "string"
      ? previewTemplates.find((item) => item.id === templateId)
      : undefined;
  const backToGallery = () => router.dismissTo("/preview");
  if (!template) {
    return (
      <View style={styles.missing}>
        <Text accessibilityRole="header" style={styles.title}>
          This template is unavailable
        </Text>
        <Text style={styles.body}>
          Choose a template from the sample shelf to start a new local preview.
        </Text>
        <Button label="All templates" onPress={backToGallery} />
      </View>
    );
  }
  return (
    <PreviewApp key={template.id} template={template} onBack={backToGallery} />
  );
}

const styles = StyleSheet.create({
  missing: {
    flex: 1,
    justifyContent: "center",
    padding: space.lg,
    gap: space.md,
    backgroundColor: colors.canvas,
  },
  title: { color: colors.ink, fontSize: 25, lineHeight: 33, fontWeight: "600" },
  body: { color: colors.muted, fontSize: 16, lineHeight: 24 },
});
