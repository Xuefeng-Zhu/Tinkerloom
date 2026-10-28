import React, { useState } from "react";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { colors, space } from "../components/theme";
import { CustomizeForm } from "./CustomizeForm";
import { PreviewForm } from "./PreviewForm";
import {
  addPreviewRecord,
  createPreviewSession,
  PreviewRecord,
  PreviewTemplate,
  resetPreviewSession,
  updatePreviewRecord,
  Values,
} from "./model";
import { headingFont, PreviewButton, styles as shared } from "./ui";

export function PreviewApp({
  template,
  onBack,
}: {
  template: PreviewTemplate;
  onBack: () => void;
}) {
  const [session, setSession] = useState(() => createPreviewSession(template));
  const [editor, setEditor] = useState<PreviewRecord | "new" | null>(null);
  const [customizing, setCustomizing] = useState(false);
  const [error, setError] = useState("");
  const booleanField = session.definition.fields.find(
    (field) => field.kind === "boolean",
  );
  const completed = booleanField
    ? session.records.filter(
        (record) => record.values[booleanField.id] === true,
      ).length
    : null;

  function save(values: Values) {
    const next =
      editor && editor !== "new"
        ? updatePreviewRecord(session, editor.id, values)
        : addPreviewRecord(session, values);
    setSession(next);
    setEditor(null);
  }

  function toggle(record: PreviewRecord, fieldId: string) {
    try {
      setSession(
        updatePreviewRecord(session, record.id, {
          ...record.values,
          [fieldId]: !record.values[fieldId],
        }),
      );
      setError("");
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "Could not change this sample.",
      );
    }
  }

  return (
    <View style={styles.screen}>
      <ScrollView
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
      >
        <View style={styles.topline}>
          <Pressable
            accessibilityRole="button"
            onPress={onBack}
            style={styles.back}
          >
            <Text style={styles.backText}>← All templates</Text>
          </Pressable>
          <View style={styles.previewBadge}>
            <Text style={styles.previewBadgeText}>LOCAL PREVIEW</Text>
          </View>
        </View>
        <View style={styles.header}>
          <Text accessibilityRole="header" style={styles.title}>
            {session.definition.title}
          </Text>
          <Text style={styles.description}>
            {session.definition.description}
          </Text>
        </View>
        <View style={styles.notice}>
          <Text style={styles.noticeTitle}>A little space to experiment</Text>
          <Text style={styles.noticeBody}>
            This is sample data in memory. Try editing it or changing the
            labels. Leaving this preview resets your changes.
          </Text>
        </View>
        <View style={styles.toolbar}>
          <Text style={styles.count}>
            {session.records.length} records
            {completed !== null ? ` · ${completed} completed` : ""}
          </Text>
          <View style={styles.toolbarActions}>
            <PreviewButton
              label="Customize"
              quiet
              onPress={() => setCustomizing(true)}
            />
            <PreviewButton
              label="Add record"
              onPress={() => setEditor("new")}
            />
          </View>
        </View>
        {error ? (
          <Text accessibilityRole="alert" style={shared.error}>
            {error}
          </Text>
        ) : null}
        <View style={styles.records}>
          {session.records.map((record) => (
            <View key={record.id} style={styles.card}>
              <View style={styles.cardHeader}>
                <Text
                  accessibilityRole="header"
                  style={[
                    styles.recordTitle,
                    booleanField &&
                      record.values[booleanField.id] === true &&
                      styles.done,
                  ]}
                >
                  {String(record.values[session.definition.primaryFieldId])}
                </Text>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={`Edit ${record.values[session.definition.primaryFieldId]}`}
                  onPress={() => setEditor(record)}
                  style={styles.editButton}
                >
                  <Text style={styles.editText}>Edit</Text>
                </Pressable>
              </View>
              {session.definition.fields
                .filter(
                  (field) => field.id !== session.definition.primaryFieldId,
                )
                .map((field) =>
                  field.kind === "boolean" ? (
                    <Pressable
                      key={field.id}
                      accessibilityRole="checkbox"
                      accessibilityLabel={field.label}
                      accessibilityState={{
                        checked: record.values[field.id] === true,
                      }}
                      onPress={() => toggle(record, field.id)}
                      style={styles.checkRow}
                    >
                      <View
                        style={[
                          styles.check,
                          record.values[field.id] === true && styles.checked,
                        ]}
                      >
                        <Text style={styles.checkMark}>
                          {record.values[field.id] === true ? "✓" : ""}
                        </Text>
                      </View>
                      <Text style={styles.checkLabel}>{field.label}</Text>
                    </Pressable>
                  ) : record.values[field.id] ? (
                    <View key={field.id} style={styles.field}>
                      <Text style={styles.fieldLabel}>{field.label}</Text>
                      <Text
                        numberOfLines={
                          field.kind === "longText" ? 3 : undefined
                        }
                        style={[
                          styles.value,
                          field.kind === "choice" && styles.choice,
                        ]}
                      >
                        {String(record.values[field.id])}
                      </Text>
                    </View>
                  ) : null,
                )}
            </View>
          ))}
        </View>
        <View style={styles.footer}>
          <Text style={styles.footerText}>
            Your signed-in workspaces and apps are separate from this preview.
          </Text>
          <PreviewButton
            label="Reset preview"
            quiet
            onPress={() => {
              setSession(resetPreviewSession(session));
              setError("");
            }}
          />
        </View>
      </ScrollView>
      {editor ? (
        <PreviewForm
          definition={session.definition}
          record={editor === "new" ? undefined : editor}
          onSave={save}
          onClose={() => setEditor(null)}
        />
      ) : null}
      {customizing ? (
        <CustomizeForm
          session={session}
          onSave={(next) => {
            setSession(next);
            setCustomizing(false);
          }}
          onClose={() => setCustomizing(false)}
        />
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.canvas },
  content: {
    width: "100%",
    maxWidth: 880,
    alignSelf: "center",
    padding: space.lg,
    gap: space.lg,
    paddingBottom: space.xxl,
  },
  topline: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    flexWrap: "wrap",
    gap: space.sm,
  },
  back: { minHeight: 44, justifyContent: "center" },
  backText: { color: colors.ink, fontSize: 15, fontWeight: "600" },
  previewBadge: {
    backgroundColor: colors.accentSoft,
    borderRadius: 4,
    paddingHorizontal: 10,
    paddingVertical: 7,
  },
  previewBadgeText: {
    color: colors.accent,
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 1,
  },
  header: { gap: space.sm },
  title: {
    fontFamily: headingFont,
    fontSize: 38,
    lineHeight: 46,
    color: colors.ink,
  },
  description: {
    color: colors.muted,
    fontSize: 16,
    lineHeight: 25,
    maxWidth: 580,
  },
  notice: {
    backgroundColor: colors.sage,
    borderRadius: 8,
    padding: space.md,
    gap: space.xs,
  },
  noticeTitle: { color: colors.ink, fontWeight: "600", fontSize: 14 },
  noticeBody: { color: colors.ink, fontSize: 14, lineHeight: 22 },
  toolbar: {
    gap: space.md,
    flexDirection: "row",
    flexWrap: "wrap",
    alignItems: "center",
    justifyContent: "space-between",
  },
  count: { color: colors.muted, fontSize: 14 },
  toolbarActions: { gap: space.sm, flexDirection: "row", flexWrap: "wrap" },
  records: { gap: space.md },
  card: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: space.lg,
    gap: space.md,
  },
  cardHeader: {
    flexDirection: "row",
    gap: space.md,
    alignItems: "center",
    justifyContent: "space-between",
  },
  recordTitle: {
    color: colors.ink,
    fontSize: 20,
    fontWeight: "600",
    lineHeight: 28,
    flex: 1,
  },
  done: { textDecorationLine: "line-through", color: colors.muted },
  editButton: {
    minWidth: 48,
    minHeight: 44,
    justifyContent: "center",
    alignItems: "center",
  },
  editText: { color: colors.accent, fontWeight: "600", fontSize: 14 },
  field: { gap: space.xs, alignItems: "flex-start" },
  fieldLabel: { color: colors.muted, fontSize: 12, fontWeight: "500" },
  value: { color: colors.ink, fontSize: 15, lineHeight: 23 },
  choice: {
    backgroundColor: colors.canvas,
    borderRadius: 4,
    paddingHorizontal: space.sm,
    paddingVertical: space.xs,
    overflow: "hidden",
    fontSize: 13,
  },
  checkRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    minHeight: 44,
  },
  check: {
    width: 24,
    height: 24,
    borderWidth: 1,
    borderColor: colors.muted,
    borderRadius: 6,
    alignItems: "center",
    justifyContent: "center",
  },
  checked: { backgroundColor: colors.ink, borderColor: colors.ink },
  checkMark: { color: colors.surface, fontSize: 16, fontWeight: "600" },
  checkLabel: { color: colors.ink, fontSize: 14 },
  footer: {
    borderTopWidth: 1,
    borderTopColor: colors.border,
    paddingTop: space.lg,
    gap: space.md,
    alignItems: "flex-start",
  },
  footerText: { color: colors.muted, fontSize: 13, lineHeight: 21 },
});
