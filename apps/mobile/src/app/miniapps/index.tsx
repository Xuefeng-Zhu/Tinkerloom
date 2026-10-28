import { router } from "expo-router";
import { ScrollView, Text, View } from "react-native";
import { Button } from "../../components/Button";
import { Notice } from "../../components/Notice";
import { fullTemplates } from "../../full/catalog";
import { styles } from "../../live/LiveAppScreen";

export default function FullTemplateGallery() {
  return (
    <ScrollView contentContainerStyle={styles.content}>
      <Button
        label="← Sample shelf"
        variant="quiet"
        onPress={() => router.replace("/preview")}
      />
      <Text style={styles.eyebrow}>MORE THREADS TO FOLLOW</Text>
      <Text accessibilityRole="header" style={styles.title}>
        Small apps, more possibilities.
      </Text>
      <Notice text="These previews use sample records in memory. They do not write to your account, schedule reminders, upload private files, or control your device. Closing a preview clears its sample changes." />
      {fullTemplates.map((template) => (
        <View key={template.id} style={styles.card}>
          <Text accessibilityRole="header" style={styles.sectionTitle}>
            {template.spec.name}
          </Text>
          <Text style={styles.body}>{template.caption}</Text>
          <Button
            label={`Preview ${template.spec.name}`}
            variant="secondary"
            onPress={() =>
              router.push({
                pathname: "/miniapps/[templateId]",
                params: { templateId: template.id },
              })
            }
          />
        </View>
      ))}
    </ScrollView>
  );
}
