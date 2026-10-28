import { useState } from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import type { LiveRecord } from "../backend/types";
import { Button } from "../components/Button";
import { Notice } from "../components/Notice";
import { colors, space } from "../components/theme";
import type {
  LiveAppController,
  LiveAppState,
} from "../state/liveAppController";
import type { Values } from "../preview/model";
import { RecordEditor } from "./RecordEditor";
import { savePresentation } from "./saveStatus";
import { RecordsView } from "./RecordsView";

export function PendingSaveNotice({
  state,
  controller,
}: {
  state: LiveAppState;
  controller: LiveAppController;
}) {
  const presentation = savePresentation(
    state.pending?.kind ?? null,
    state.busy,
  );
  if (!presentation) return null;
  return (
    <View style={styles.pending}>
      <Text accessibilityLiveRegion="polite" style={styles.sectionTitle}>
        {presentation.title}
      </Text>
      <Text style={styles.body}>{presentation.description}</Text>
      {presentation.canRetry && (
        <Button
          label="Retry same save"
          busy={state.busy}
          onPress={() => {
            void controller.retry();
          }}
        />
      )}
    </View>
  );
}

export function LiveAppScreen({
  state,
  controller,
  onBack,
  onEdit,
  onShare,
}: {
  state: LiveAppState;
  controller: LiveAppController;
  onBack: () => void;
  onEdit: () => void;
  onShare: () => void;
}) {
  const [editor, setEditor] = useState<{ record: LiveRecord | null } | null>(
    null,
  );
  const app = state.app;
  const definition = app?.publishedDefinition;
  async function save(values: Values) {
    await controller.writeRecord(editor?.record ?? null, values);
    if (controller.getSnapshot().notice === "Record saved.") setEditor(null);
  }
  return (
    <View style={styles.fill}>
      <ScrollView
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
      >
        <View style={styles.toolbar}>
          <Button label="← Workbench" variant="quiet" onPress={onBack} />
          <Button
            label="Refresh"
            variant="quiet"
            onPress={() => {
              void controller.load();
            }}
            disabled={state.busy || state.loading}
          />
        </View>
        {state.error && <Notice text={state.error} error />}
        {state.notice && <Notice text={state.notice} />}
        <PendingSaveNotice state={state} controller={controller} />
        {!app ? (
          <Text style={styles.body}>
            {state.loading || !state.error
              ? "Opening app…"
              : "This app is unavailable. Return to your workbench or refresh."}
          </Text>
        ) : (
          <>
            <Text style={styles.eyebrow}>
              {definition ? "YOUR LIVE APP" : "START BUILDING"}
            </Text>
            <Text accessibilityRole="header" style={styles.title}>
              {definition?.title ?? app.name}
            </Text>
            <Text style={styles.body}>
              {definition?.description ??
                "Choose a template, customize its fields, then publish it for your own live records."}
            </Text>
            <View style={styles.toolbar}>
              {app.capabilities?.editDefinition === true && (
                <Button
                  label="Open builder"
                  onPress={onEdit}
                  disabled={state.busy}
                />
              )}
              <Button
                label="People and sharing"
                variant="quiet"
                onPress={onShare}
                disabled={state.busy}
              />
              {definition && app.capabilities?.writeRecords === true && (
                <Button
                  label="New record"
                  variant="secondary"
                  disabled={
                    state.busy || state.loading || Boolean(state.pending)
                  }
                  onPress={() => setEditor({ record: null })}
                />
              )}
            </View>
            {definition && (
              <>
                <Text style={styles.version}>
                  Published version {app.publishedRevision}
                  {(app.candidateRevision ?? 0) > app.publishedRevision
                    ? " · Newer draft available in the builder"
                    : ""}
                </Text>
                {app.archived && (
                  <Notice text="This app is archived. Published records remain readable." />
                )}
                <Text style={styles.hint}>
                  These are live records saved through Appwrite. Local preview
                  samples are never copied here.
                </Text>
                <Text style={styles.hint}>
                  Loaded records only · {state.records.length} loaded.
                  {state.nextCursor
                    ? " Load more to include the next page."
                    : ""}
                </Text>
                {definition.view?.kind === "agenda" && (
                  <Text style={styles.hint}>
                    Dates group the loaded records. This is an agenda, with no
                    full-calendar totals.
                  </Text>
                )}
                {state.records.length === 0 && !state.loading ? (
                  <View style={styles.card}>
                    <Text style={styles.sectionTitle}>A fresh start</Text>
                    <Text style={styles.body}>
                      Add your first record to this app.
                    </Text>
                  </View>
                ) : (
                  <RecordsView
                    definition={definition}
                    records={state.records}
                    onEdit={(record) => setEditor({ record })}
                    editDisabled={
                      state.busy ||
                      state.loading ||
                      Boolean(state.pending) ||
                      app.capabilities?.writeRecords !== true
                    }
                  />
                )}
                {state.loading && (
                  <Text accessibilityLiveRegion="polite" style={styles.body}>
                    Loading records…
                  </Text>
                )}
                {state.nextCursor && (
                  <Button
                    label="Load more records"
                    variant="secondary"
                    disabled={state.loading || state.busy}
                    onPress={() => {
                      void controller.loadMore();
                    }}
                  />
                )}
              </>
            )}
          </>
        )}
      </ScrollView>
      {editor && definition && app?.capabilities?.writeRecords === true && (
        <RecordEditor
          key={editor.record?.id ?? "new"}
          definition={definition}
          record={editor.record}
          busy={state.busy}
          locked={Boolean(state.pending)}
          error={state.error}
          onSave={(values) => {
            void save(values);
          }}
          onClose={() => setEditor(null)}
        />
      )}
    </View>
  );
}

export const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.canvas },
  content: {
    padding: space.lg,
    gap: space.lg,
    width: "100%",
    maxWidth: 900,
    alignSelf: "center",
    paddingBottom: space.xxl,
  },
  toolbar: {
    flexDirection: "row",
    flexWrap: "wrap",
    justifyContent: "space-between",
    alignItems: "center",
    gap: space.md,
  },
  eyebrow: {
    color: colors.accent,
    letterSpacing: 2,
    fontSize: 11,
    fontWeight: "700",
  },
  title: { color: colors.ink, fontSize: 36, lineHeight: 43, fontWeight: "700" },
  sectionTitle: {
    color: colors.ink,
    fontSize: 18,
    lineHeight: 25,
    fontWeight: "600",
  },
  body: { color: colors.muted, fontSize: 16, lineHeight: 24 },
  hint: { color: colors.muted, fontSize: 13, lineHeight: 21 },
  version: { color: colors.accent, fontSize: 13, fontWeight: "600" },
  card: {
    padding: space.lg,
    gap: space.md,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
  },
  recordTitle: { fontSize: 21, color: colors.ink, fontWeight: "600", flex: 1 },
  fieldLabel: {
    color: colors.ink,
    fontWeight: "600",
    fontSize: 13,
    marginBottom: space.xs,
  },
  pending: {
    padding: space.md,
    gap: space.md,
    backgroundColor: colors.accentSoft,
    borderRadius: 12,
  },
});
