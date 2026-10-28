import { useState } from "react";
import { ScrollView, Text, View } from "react-native";
import { Button } from "../components/Button";
import { Field } from "../components/Field";
import { Notice } from "../components/Notice";
import { previewTemplates } from "../preview/catalog";
import type { Definition, Field as DefinitionField } from "../preview/model";
import type {
  LiveAppController,
  LiveAppState,
  PublicationReview,
} from "../state/liveAppController";
import { PendingSaveNotice, styles } from "./LiveAppScreen";
import { RecordViewPicker } from "./RecordViewPicker";

export function BuilderScreen({
  state,
  controller,
  onBack,
}: {
  state: LiveAppState;
  controller: LiveAppController;
  onBack: () => void;
}) {
  const [reviewedRevision, setReviewedRevision] =
    useState<PublicationReview | null>(null);
  const app = state.app;
  const definition =
    state.editingDefinition ?? app?.definition ?? app?.publishedDefinition;
  const inactive = state.busy || state.loading || Boolean(state.pending);
  const dirty = state.editingDefinition !== null;
  const staleBase = Boolean(
    app?.definition && app.basePublishedRevision !== app.publishedRevision,
  );
  function edit(next: Definition) {
    setReviewedRevision(null);
    controller.editDefinition(next);
  }
  function addField(kind: DefinitionField["kind"]) {
    if (!definition || definition.fields.length >= 10) return;
    let number = definition.fields.length + 1;
    while (definition.fields.some((field) => field.id === `field_${number}`))
      number++;
    edit({
      ...definition,
      fields: [
        ...definition.fields,
        {
          id: `field_${number}`,
          label:
            kind === "number"
              ? "Number"
              : kind === "date"
                ? "Date"
                : "New field",
          kind,
          ...(kind === "choice" ? { options: ["First", "Second"] } : {}),
        },
      ],
    });
  }
  if (app && app.capabilities?.editDefinition !== true)
    return (
      <ScrollView contentContainerStyle={styles.content}>
        <Button label="← App" variant="quiet" onPress={onBack} />
        <Text accessibilityRole="header" style={styles.title}>
          {app.name}
        </Text>
        <Notice
          text={
            app.archived
              ? "This app is archived. Its published records are read only."
              : "Your role can view the published app. Editing its structure needs builder access."
          }
        />
      </ScrollView>
    );
  return (
    <ScrollView
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
    >
      <View style={styles.toolbar}>
        <Button label="← App" variant="quiet" onPress={onBack} />
        <Button
          label="Refresh saved app"
          variant="quiet"
          disabled={state.busy || state.loading}
          onPress={() => {
            void controller.load();
          }}
        />
      </View>
      <Text style={styles.eyebrow}>MAKE IT YOUR OWN</Text>
      <Text accessibilityRole="header" style={styles.title}>
        {app?.name ?? "App builder"}
      </Text>
      {state.error && <Notice error text={state.error} />}
      {state.notice && <Notice text={state.notice} />}
      <PendingSaveNotice state={state} controller={controller} />
      {staleBase && (
        <Notice
          error
          text="The live version changed after this private draft began. Start from the live version or reconcile your changes before saving and reviewing a new candidate."
        />
      )}
      {app?.publishedDefinition && !state.busy && !state.pending && (
        <Button
          label="Use live version in my draft"
          variant="quiet"
          onPress={() => edit(app.publishedDefinition!)}
        />
      )}
      {!app ? (
        <Text style={styles.body}>
          {state.loading || !state.error
            ? "Loading your draft…"
            : "This app is unavailable."}
        </Text>
      ) : !definition ? (
        <>
          <Text style={styles.body}>
            Start with a template. Only its structure is saved; sample records
            stay in the local preview.
          </Text>
          {previewTemplates.map((template) => (
            <View style={styles.card} key={template.id}>
              <Text style={styles.sectionTitle}>
                {template.definition.title}
              </Text>
              <Text style={styles.body}>{template.caption}</Text>
              <Button
                label={`Use ${template.id} template`}
                disabled={inactive}
                onPress={() => edit(template.definition)}
              />
            </View>
          ))}
        </>
      ) : (
        <>
          <Text style={styles.hint}>
            Draft {app.draftRevision}
            {app.publishedRevision
              ? ` · Published version ${app.publishedRevision}`
              : " · Not published"}
            .{" "}
            {dirty
              ? "Unsaved edits are retained while this app session stays open."
              : "Changes here do not affect live records until publication."}
          </Text>
          <Field
            label="App title"
            value={definition.title}
            maxLength={80}
            editable={!inactive}
            onChangeText={(title) => edit({ ...definition, title })}
          />
          <Field
            label="Description"
            value={definition.description}
            maxLength={240}
            multiline
            editable={!inactive}
            onChangeText={(description) => edit({ ...definition, description })}
          />
          <Text accessibilityRole="header" style={styles.sectionTitle}>
            Fields
          </Text>
          <Text style={styles.hint}>
            Keep existing fields and their types to preserve records. New fields
            are optional.
          </Text>
          {definition.fields.map((field) => (
            <View key={field.id} style={styles.card}>
              <Field
                label={`${field.label} label`}
                value={field.label}
                maxLength={64}
                editable={!inactive}
                onChangeText={(label) =>
                  edit({
                    ...definition,
                    fields: definition.fields.map((item) =>
                      item.id === field.id ? { ...item, label } : item,
                    ),
                  })
                }
              />
              <Text style={styles.hint}>
                {field.kind === "longText" ? "Long text" : field.kind} ·{" "}
                {field.required ? "Required" : "Optional"}
              </Text>
              {field.kind === "choice" && (
                <Field
                  label={`${field.label} choices`}
                  hint="Separate choices with commas. Keep existing choices when updating a published app."
                  value={field.options?.join(", ") ?? ""}
                  editable={!inactive}
                  onChangeText={(text) =>
                    edit({
                      ...definition,
                      fields: definition.fields.map((item) =>
                        item.id === field.id
                          ? {
                              ...item,
                              options: text
                                .split(",")
                                .map((part) => part.trim()),
                            }
                          : item,
                      ),
                    })
                  }
                />
              )}
            </View>
          ))}
          {definition.fields.length < 10 && (
            <View style={styles.toolbar}>
              {(
                [
                  "text",
                  "longText",
                  "boolean",
                  "choice",
                  "number",
                  "date",
                ] as const
              ).map((kind) => (
                <Button
                  key={kind}
                  label={`Add ${kind === "longText" ? "long text" : kind} field`}
                  variant="secondary"
                  disabled={inactive}
                  onPress={() => addField(kind)}
                />
              ))}
            </View>
          )}
          <RecordViewPicker
            definition={definition}
            disabled={inactive}
            onChange={(view) => edit({ ...definition, view })}
          />
          <Button
            label="Save draft"
            disabled={inactive || (!dirty && app.definition !== null)}
            busy={state.busy && state.pending?.kind === "draft"}
            onPress={() => {
              void controller.saveDefinition(definition);
            }}
          />
          {dirty && (
            <Button
              label="Discard edits and reload saved draft"
              variant="quiet"
              disabled={inactive}
              onPress={() => {
                setReviewedRevision(null);
                void controller.reloadEditor();
              }}
            />
          )}
          {!dirty &&
            app.definition &&
            app.candidateRevision !== app.publishedRevision && (
              <>
                <Button
                  label="Review publication"
                  variant="secondary"
                  disabled={
                    inactive ||
                    staleBase ||
                    app.candidateRevision === undefined ||
                    app.basePublishedRevision === undefined
                  }
                  onPress={() =>
                    setReviewedRevision({
                      expectedRevision: app.draftRevision,
                      candidateRevision: app.candidateRevision!,
                      expectedPublishedRevision: app.basePublishedRevision!,
                    })
                  }
                />
                {reviewedRevision?.expectedRevision === app.draftRevision &&
                  reviewedRevision.candidateRevision ===
                    app.candidateRevision &&
                  !staleBase && (
                    <View style={styles.card}>
                      <Text
                        accessibilityRole="header"
                        style={styles.sectionTitle}
                      >
                        Publish “{app.definition.title}”
                      </Text>
                      <Text style={styles.body}>
                        This makes saved version{" "}
                        {reviewedRevision.candidateRevision} the live version of
                        this app. It includes {app.definition.fields.length}{" "}
                        fields and preserves compatible existing records.
                      </Text>
                      <Text style={styles.hint}>
                        Layout: {app.definition.view?.kind ?? "list"}
                        {app.definition.view?.kind === "agenda"
                          ? ` · Grouped by ${app.definition.fields.find((field) => field.id === app.definition?.view?.dateFieldId)?.label ?? "date"}`
                          : ""}
                      </Text>
                      {app.definition.fields.map((field) => (
                        <Text key={field.id} style={styles.hint}>
                          {field.label} · {field.kind}
                          {field.required ? " · required" : ""}
                        </Text>
                      ))}
                      <Button
                        label="Publish this version"
                        disabled={inactive}
                        busy={state.busy && state.pending?.kind === "publish"}
                        onPress={() => {
                          void controller.publish(reviewedRevision);
                        }}
                      />
                    </View>
                  )}
              </>
            )}
          {!dirty &&
            app.publishedRevision > 0 &&
            app.publishedRevision === app.candidateRevision && (
              <Notice text="The saved version is live. Open the app to use your records." />
            )}
        </>
      )}
    </ScrollView>
  );
}
