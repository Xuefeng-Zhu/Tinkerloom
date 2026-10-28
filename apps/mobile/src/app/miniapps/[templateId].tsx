import { useEffect, useRef, useState } from "react";
import { router, useLocalSearchParams } from "expo-router";
import { Text, View } from "react-native";
import { Button } from "../../components/Button";
import { fullTemplates } from "../../full/catalog";
import { styles } from "../../live/LiveAppScreen";
import { RuntimeRenderer } from "../../renderer/RuntimeRenderer";
import { createIsolatedPreview } from "../../runtime/createPreview";
import type { AppSpec } from "../../spec/types";

function PreviewSession({ spec }: { spec: AppSpec }) {
  const [session] = useState(() => createIsolatedPreview(spec));
  const references = useRef({ count: 0 });
  useEffect(() => {
    const lifetime = references.current;
    lifetime.count++;
    return () => {
      lifetime.count--;
      // Retain the same pure preview across React's development effect probe.
      void Promise.resolve().then(() => {
        if (lifetime.count === 0) session.dispose();
      });
    };
  }, [session]);
  return (
    <RuntimeRenderer
      controller={session.controller}
      timers={session.timers}
      onExit={() => router.replace("/miniapps")}
    />
  );
}

export default function FullPreviewRoute() {
  const { templateId } = useLocalSearchParams<{
    templateId?: string | string[];
  }>();
  const template = fullTemplates.find((item) => item.id === templateId);
  if (!template)
    return (
      <View style={styles.content}>
        <Text style={styles.title}>This sample is unavailable.</Text>
        <Button
          label="Browse samples"
          onPress={() => router.replace("/miniapps")}
        />
      </View>
    );
  return <PreviewSession key={template.id} spec={template.spec} />;
}
