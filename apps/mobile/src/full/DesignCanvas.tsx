import { useEffect, useState, useSyncExternalStore } from "react";
import { Pressable, Text, View, useWindowDimensions } from "react-native";
import type { AppSpec } from "../spec/types";
import { RendererContext } from "../renderer/context";
import { pageRows, resolveAppearance } from "../renderer/appearance";
import { SemanticView } from "../renderer/views";
import { Button } from "../components/Button";
import { PreviewSession } from "./PreviewSession";
import { Choices, styles } from "./ui";
export function DesignCanvas({
  spec,
  onSelectView,
  onSelectPage,
}: {
  spec: AppSpec;
  onSelectView: (id: string) => void;
  onSelectPage: (id: string) => void;
}) {
  const [preview] = useState(() => new PreviewSession(spec, "design"));
  const session = useSyncExternalStore(
    preview.subscribe,
    preview.getSnapshot,
    preview.getSnapshot,
  );
  const controller = session.session.controller,
    state = useSyncExternalStore(
      controller.subscribe,
      controller.getSnapshot,
      controller.getSnapshot,
    ),
    theme = resolveAppearance(spec),
    dimensions = useWindowDimensions();
  useEffect(() => {
    preview.update(spec);
  }, [preview, spec]);
  useEffect(() => () => preview.dispose(), [preview]);
  useEffect(() => {
    void controller.refresh();
  }, [controller, spec]);
  const pages = spec.navigation?.pages ?? [
      {
        id: "__legacy__",
        title: spec.name,
        viewIds: spec.views.map((v) => v.id),
      },
    ],
    page = pages.find((p) => p.id === state.location.pageId) ?? pages[0];
  const views = page.viewIds.flatMap((id) =>
      spec.views.filter((v) => v.id === id),
    ),
    rows = pageRows(page, views, dimensions.width, dimensions.fontScale);
  const context = {
    controller,
    state,
    theme,
    timers: session.session.timers,
    navigate: () => {},
    openRecord: () => {},
    edit: () => {},
  };
  return (
    <View style={{ gap: 12 }}>
      {pages.length > 1 && (
        <Choices
          label="Canvas page"
          values={pages.map((p) => p.id)}
          value={page.id}
          onChange={(pageId) => controller.navigate({ pageId }, true)}
        />
      )}
      <Button
        label={`Inspect page: ${page.title}`}
        variant="secondary"
        onPress={() => onSelectPage(page.id)}
      />
      <RendererContext.Provider value={context}>
        <View
          style={{
            backgroundColor: theme.canvas,
            padding: theme.spacing,
            gap: theme.spacing,
            borderRadius: theme.radius,
          }}
        >
          {rows.map((row, index) => (
            <View
              key={index}
              style={{
                flexDirection: "row",
                gap: theme.spacing,
                alignItems: "flex-start",
              }}
            >
              {row.map((view) => (
                <Pressable
                  key={view.id}
                  accessibilityRole="button"
                  accessibilityLabel={`Inspect ${view.label}, ${view.type} view`}
                  onPress={() => onSelectView(view.id)}
                  style={{
                    flex: 1,
                    minWidth: 0,
                    borderWidth: 1,
                    borderStyle: "dashed",
                    borderColor: theme.accent,
                    borderRadius: theme.radius,
                    padding: 6,
                    minHeight: 44,
                  }}
                >
                  <Text style={styles.muted}>Inspect {view.label}</Text>
                  <View
                    pointerEvents="none"
                    accessibilityElementsHidden
                    importantForAccessibility="no-hide-descendants"
                  >
                    <SemanticView view={view} />
                  </View>
                </Pressable>
              ))}
            </View>
          ))}
        </View>
      </RendererContext.Provider>
    </View>
  );
}
