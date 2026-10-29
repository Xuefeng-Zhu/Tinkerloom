import type { ReactNode } from "react";
import { Pressable, Text, View, useWindowDimensions } from "react-native";
import { styles } from "./ui";
export function builderWorkspaceLayout(width: number, fontScale: number) {
  const split =
    Number.isFinite(width) &&
    width >= 850 &&
    Number.isFinite(fontScale) &&
    fontScale < 1.5;
  return { split, chatWidth: width < 1100 ? 330 : 380 };
}
/** Stable sibling positions retain one isolated sample session and local editor buffers across layouts. */
export function BuilderWorkspace({
  mode,
  disabled,
  onSelect,
  chat,
  preview,
}: {
  mode: "live" | "build" | "preview";
  disabled: boolean;
  onSelect(mode: "build" | "preview"): void;
  chat: ReactNode;
  preview: ReactNode;
}) {
  const { width, fontScale } = useWindowDimensions();
  const { split, chatWidth } = builderWorkspaceLayout(width, fontScale);
  const active = mode !== "live";
  const showChat = active && (split || mode === "build");
  const showPreview = active && (split || mode === "preview");
  return (
    <View
      style={{ flex: 1, minHeight: 0, display: active ? "flex" : "none" }}
      aria-hidden={!active}
      accessibilityElementsHidden={!active}
      importantForAccessibility={active ? "auto" : "no-hide-descendants"}
    >
      {!split && (
        <View
          accessibilityRole="tablist"
          accessibilityLabel="Private builder"
          style={[styles.row, { paddingHorizontal: 12, paddingBottom: 8 }]}
        >
          {(["build", "preview"] as const).map((item) => (
            <Pressable
              key={item}
              accessibilityRole="tab"
              accessibilityLabel={
                item === "build" ? "Chat and editor" : "Try preview"
              }
              accessibilityState={{ selected: item === mode, disabled }}
              aria-selected={item === mode}
              aria-disabled={disabled}
              disabled={disabled}
              onPress={() => onSelect(item)}
              style={[
                styles.choice,
                item === mode && styles.chosen,
                disabled && { opacity: 0.5 },
              ]}
            >
              <Text style={styles.body}>
                {item === "build" ? "Chat" : "Preview"}
              </Text>
            </Pressable>
          ))}
        </View>
      )}
      <View
        style={{
          flex: 1,
          minHeight: 0,
          flexDirection: split ? "row" : "column",
        }}
      >
        <View
          aria-hidden={!showChat}
          accessibilityElementsHidden={!showChat}
          importantForAccessibility={showChat ? "auto" : "no-hide-descendants"}
          style={{
            display: showChat ? "flex" : "none",
            flex: split ? undefined : 1,
            width: split ? chatWidth : undefined,
            minHeight: 0,
            minWidth: 0,
          }}
        >
          {chat}
        </View>
        <View
          aria-hidden={!showPreview}
          accessibilityElementsHidden={!showPreview}
          importantForAccessibility={
            showPreview ? "auto" : "no-hide-descendants"
          }
          style={{
            display: showPreview ? "flex" : "none",
            flex: 1,
            minHeight: 0,
            minWidth: 0,
          }}
        >
          {preview}
        </View>
      </View>
    </View>
  );
}
