import type { PreviewStaticImageAssets } from "../runtime/previewImageAssets";
import {
  createContext,
  useContext,
  useLayoutEffect,
  useState,
  useRef,
  useSyncExternalStore,
} from "react";
import { InspectorFlushQueue } from "./inspectorSelection";
import {
  InspectorTextDraft,
  InspectorInputRegistry,
} from "./inspectorTextDraft";
import { Text, View } from "react-native";
import { Button } from "../components/Button";
import { Field } from "../components/Field";
import { Notice } from "../components/Notice";
import {
  ACTION_CAPABILITIES,
  FIELD_TYPES,
  VIEW_TYPES,
  type ActionSpec,
  type AppSpec,
  type AutomationSpec,
  type FieldType,
  type PageSpec,
  type ViewSpec,
  type ViewType,
} from "../spec/types";
import { CONTENT_VIEW_TYPES } from "../spec/bindings";
import { canonicalJson } from "../spec/schema";
import type { SemanticEdit } from "./semanticEdits";
import { DesignCanvas } from "./DesignCanvas";
import { Card, Choices, Toggle, styles } from "./ui";

type Section =
  | "design"
  | "fields"
  | "views"
  | "actions"
  | "pages"
  | "appearance"
  | "reminders"
  | "JSON";
const InspectorFlushContext = createContext<{
  flush: () => Promise<boolean>;
  resetEpoch: number;
  register: (input: InspectorTextDraft) => () => void;
  accepted: () => void;
} | null>(null);
function LabelInput({
  identity,
  label,
  value,
  onChange,
  disabled = false,
}: {
  identity: string;
  label: string;
  value: string;
  onChange: (text: string) => boolean | void;
  disabled?: boolean;
}) {
  const context = useContext(InspectorFlushContext);
  const resetEpoch = context?.resetEpoch ?? 0;
  const register = context?.register;
  const [draft] = useState(
    () => new InspectorTextDraft(value, identity, resetEpoch),
  );
  const text = useSyncExternalStore(
    draft.subscribe,
    draft.getSnapshot,
    draft.getSnapshot,
  );
  useLayoutEffect(() => {
    draft.activate();
    return () => draft.dispose();
  }, [draft]);
  useLayoutEffect(() => {
    draft.configure(value, identity, resetEpoch);
  }, [draft, value, identity, resetEpoch]);
  useLayoutEffect(() => register?.(draft), [register, draft]);
  return (
    <Field
      label={label}
      value={draft.matches(identity, resetEpoch) ? text : value}
      editable={!disabled}
      onFocus={() => draft.focus()}
      onBlur={() => {
        void draft.blur(() => context?.flush() ?? Promise.resolve(true));
      }}
      onChangeText={(text) => {
        draft.change(text, false);
        try {
          if (onChange(text) === false) draft.reject();
          else {
            draft.accept();
            context?.accepted();
          }
        } catch (error) {
          draft.reject();
          throw error;
        }
      }}
    />
  );
}

function JsonDetails({
  label,
  value,
  onApply,
  disabled,
}: {
  label: string;
  value: unknown;
  onApply: (value: unknown) => void;
  disabled: boolean;
}) {
  const [expanded, setExpanded] = useState(false),
    [draft, setDraft] = useState(""),
    [error, setError] = useState<string | null>(null);
  return (
    <View style={{ gap: 8 }}>
      <Button
        label={expanded ? `Close ${label}` : `Advanced ${label}`}
        variant="quiet"
        onPress={() => {
          setExpanded(!expanded);
          setDraft(JSON.stringify(value, null, 2));
          setError(null);
        }}
      />
      {expanded && (
        <>
          <Field
            label={label}
            multiline
            value={draft}
            editable={!disabled}
            onChangeText={setDraft}
          />
          {error && <Notice text={error} error />}
          <Button
            label={`Apply ${label}`}
            disabled={disabled}
            variant="secondary"
            onPress={() => {
              try {
                onApply(JSON.parse(draft));
                setError(null);
              } catch (issue) {
                setError(
                  issue instanceof Error ? issue.message : "Invalid JSON.",
                );
              }
            }}
          />
        </>
      )}
    </View>
  );
}
function defaultView(
  type: ViewType,
  spec: AppSpec,
  collectionId: string,
): Omit<ViewSpec, "id"> {
  const collection =
      spec.collections.find((c) => c.id === collectionId) ??
      spec.collections[0],
    fields = collection?.fields ?? [];
  const base = {
    type,
    label: `New ${type}`,
    actionIds: spec.actions
      .filter(
        (action) =>
          action.collectionId === collection?.id &&
          (type === "form"
            ? ["records.create.v1", "records.patch.v1"].includes(
                action.capability,
              )
            : type === "board"
              ? action.capability === "workflow.transition.v1"
              : type === "checklist"
                ? action.capability === "records.patch.v1"
                : type === "capacity"
                  ? action.capability.startsWith("capacity.")
                  : type === "action"),
      )
      .map((action) => action.id),
    ...(CONTENT_VIEW_TYPES.has(type)
      ? {}
      : { collectionId: collection?.id ?? "" }),
  };
  const date = fields.find((f) => f.type === "timestamp")?.id ?? "",
    image = fields.find((f) => f.type === "image")?.id ?? "";
  const options: Partial<Record<ViewType, unknown>> = {
    clock: { style: "digital" },
    timer: { durationMinutes: 25 },
    deviceInfo: { fields: ["batteryLevel"] },
    deviceControl: { control: "flashlight" },
    richText: { markdown: "Write a useful note." },
    banner: { title: "Welcome" },
    calendar: { dateFieldId: date },
    timeline: { dateFieldId: date },
    metric: { metric: "count" },
    chart: { style: "bar", metric: "count" },
    imageCards: { imageFieldId: image },
    gallery: { imageFieldId: image },
    checklist: {
      fieldId: fields.find((f) => f.type === "boolean")?.id ?? "",
      actionId:
        spec.actions.find(
          (a) =>
            a.collectionId === collection?.id &&
            a.capability === "records.patch.v1",
        )?.id ?? "",
    },
  };
  return {
    ...base,
    ...(options[type] ? { options: options[type] } : {}),
    ...(type === "board"
      ? { groupByFieldId: fields.find((f) => f.type === "choice")?.id ?? "" }
      : {}),
  } as Omit<ViewSpec, "id">;
}
export function SpecEditor({
  spec,
  staticImageAssets,
  disabled,
  onEdit,
  onReplace,
  onFlush,
  editorResetEpoch = 0,
  registerInputGuard,
}: {
  spec: AppSpec;
  staticImageAssets?: PreviewStaticImageAssets;
  disabled: boolean;
  onEdit: (edit: SemanticEdit, debounce?: boolean) => void;
  onReplace: (value: unknown) => void;
  onFlush?: () => Promise<boolean>;
  editorResetEpoch?: number;
  registerInputGuard?: (
    guard: () => boolean,
    subscribe: (listener: () => void) => () => void,
  ) => () => void;
}) {
  const [section, setSection] = useState<Section>("design"),
    [error, setError] = useState<{ message: string; epoch: number } | null>(
      null,
    ),
    [collectionId, setCollection] = useState(spec.collections[0]?.id ?? ""),
    [viewId, setView] = useState(spec.views[0]?.id ?? ""),
    [pageId, setPage] = useState(spec.navigation?.pages[0]?.id ?? ""),
    [actionId, setAction] = useState(spec.actions[0]?.id ?? ""),
    [fieldId, setField] = useState(spec.collections[0]?.fields[0]?.id ?? "");
  const errorRef = useRef<typeof error>(null);
  const [inputs] = useState(() => new InspectorInputRegistry());
  useLayoutEffect(
    () => registerInputGuard?.(inputs.canFlush, inputs.subscribe),
    [registerInputGuard, inputs],
  );
  const [inspector] = useState(
    () =>
      new InspectorFlushQueue({
        flush: () => Promise.resolve(false),
        spec: () => spec,
        available: () => !disabled,
        select: (target) => {
          if (target.kind === "app") setSection("appearance");
          if (target.kind === "view") {
            setView(target.viewId);
            setSection("views");
          }
          if (target.kind === "page") {
            setPage(target.pageId);
            setSection("pages");
          }
          if (target.kind === "field") {
            setCollection(target.collectionId);
            setField(target.fieldId);
            setSection("fields");
          }
        },
      }),
  );
  useLayoutEffect(() => {
    inspector.activate();
    return () => inspector.dispose();
  }, [inspector]);
  useLayoutEffect(() => {
    inspector.configure({
      flush: () =>
        errorRef.current?.epoch === editorResetEpoch || !inputs.canFlush()
          ? Promise.resolve(false)
          : (onFlush?.() ?? Promise.resolve(true)),
      spec: () => spec,
      available: () => !disabled,
    });
  }, [inspector, spec, disabled, onFlush, editorResetEpoch, inputs]);
  const navigationDisabled = disabled && !inspector.flushing;
  const collection =
      spec.collections.find((c) => c.id === collectionId) ??
      spec.collections[0],
    view = spec.views.find((v) => v.id === viewId) ?? spec.views[0],
    page =
      spec.navigation?.pages.find((p) => p.id === pageId) ??
      spec.navigation?.pages[0],
    action = spec.actions.find((a) => a.id === actionId) ?? spec.actions[0];
  const [fieldLabel, setFieldLabel] = useState(""),
    [fieldType, setFieldType] = useState<FieldType>("text"),
    [choices, setChoices] = useState(""),
    [fieldViews, setFieldViews] = useState<string[]>([]),
    [newViewType, setNewViewType] = useState<ViewType>("list");
  const apply = (edit: SemanticEdit, debounce = false) => {
    try {
      onEdit(edit, debounce);
      if (inputs.canFlush()) {
        errorRef.current = null;
        setError(null);
      }
      return true;
    } catch (issue) {
      setError({
        message:
          issue instanceof Error ? issue.message : "This change is invalid.",
        epoch: editorResetEpoch,
      });
      return false;
    }
  };
  const updateView = (changes: Record<string, unknown>) => {
    if (!view) return;
    const { id, ...definition } = view;
    return apply({
      type: "UpdateView",
      viewId: id,
      view: { ...definition, ...changes } as Omit<ViewSpec, "id">,
    });
  };
  const updatePage = (changes: Partial<PageSpec>) => {
    if (!page) return;
    const { id, ...definition } = page;
    return apply({
      type: "UpdatePage",
      pageId: id,
      page: { ...definition, ...changes },
    });
  };
  const toggled = (items: string[], id: string, value: boolean) =>
    value ? [...items, id] : items.filter((v) => v !== id);
  const options = view?.options as Record<string, unknown> | undefined;
  const updateOptions = (changes: Record<string, unknown>) =>
    updateView({ options: { ...options, ...changes } });
  const content = (
    <View style={{ gap: 16 }}>
      <Choices
        label="Edit your declaration"
        disabled={navigationDisabled}
        values={
          [
            "design",
            "fields",
            "views",
            "actions",
            "pages",
            "appearance",
            "reminders",
            "JSON",
          ] as const
        }
        value={section}
        onChange={(next) => {
          void inspector.transition(() => setSection(next));
        }}
      />
      {error?.epoch === editorResetEpoch && (
        <Notice text={error.message} error />
      )}
      {section === "design" && (
        <Card title="Design canvas">
          <Text style={styles.body}>
            Select a component to inspect it. Design mode never runs record
            actions; switch to Try preview to test with isolated sample data.
          </Text>
          <LabelInput
            identity="app:name"
            label="App name"
            value={spec.name}
            disabled={disabled}
            onChange={(label) =>
              apply({ type: "RenameLabel", targetId: "app", label }, true)
            }
          />
          <DesignCanvas
            staticImageAssets={staticImageAssets}
            spec={spec}
            disabled={navigationDisabled}
            onSelectApp={() => {
              void inspector.inspect({ kind: "app" });
            }}
            onSelectField={(collectionId, fieldId) => {
              void inspector.inspect({
                kind: "field",
                collectionId,
                fieldId,
              });
            }}
            onSelectView={(viewId) => {
              void inspector.inspect({ kind: "view", viewId });
            }}
            onSelectPage={(pageId) => {
              void inspector.inspect({ kind: "page", pageId });
            }}
          />
        </Card>
      )}
      {section === "fields" && (
        <Card title="Collections and fields">
          {collection ? (
            <>
              <Choices
                label="Collection"
                values={spec.collections.map((c) => c.id)}
                value={collection.id}
                disabled={navigationDisabled}
                onChange={(next) => {
                  void inspector.transition(() => setCollection(next));
                }}
              />
              <LabelInput
                identity={`collection:${collection.id}:label`}
                label="Collection label"
                value={collection.label}
                disabled={disabled}
                onChange={(label) =>
                  apply(
                    { type: "RenameLabel", targetId: collection.id, label },
                    true,
                  )
                }
              />
              <Choices
                label="Inspect field"
                disabled={navigationDisabled}
                values={collection.fields.map((field) => field.id)}
                value={
                  collection.fields.some((field) => field.id === fieldId)
                    ? fieldId
                    : (collection.fields[0]?.id ?? "")
                }
                onChange={(next) => {
                  void inspector.transition(() => setField(next));
                }}
              />
              {collection.fields
                .filter(
                  (field) =>
                    field.id ===
                    (collection.fields.some((item) => item.id === fieldId)
                      ? fieldId
                      : collection.fields[0]?.id),
                )
                .map((field) => (
                  <View key={field.id} style={styles.card}>
                    <Text style={styles.muted}>
                      {field.id} · {field.type} ·{" "}
                      {field.required ? "Required" : "Optional"}
                    </Text>
                    <LabelInput
                      identity={`field:${collection.id}:${field.id}:label`}
                      label={`${field.id} label`}
                      value={field.label}
                      disabled={disabled}
                      onChange={(label) =>
                        apply(
                          {
                            type: "RenameField",
                            collectionId: collection.id,
                            fieldId: field.id,
                            label,
                          },
                          true,
                        )
                      }
                    />
                    {field.type === "choice" && (
                      <ChoiceAdder
                        choices={field.choices ?? []}
                        disabled={disabled}
                        onAdd={(choice) =>
                          apply({
                            type: "AddChoice",
                            collectionId: collection.id,
                            fieldId: field.id,
                            choice,
                          })
                        }
                      />
                    )}
                  </View>
                ))}
              <Text style={styles.title}>Add an optional field</Text>
              <Field
                label="Field label"
                value={fieldLabel}
                editable={!disabled}
                onChangeText={setFieldLabel}
              />
              <Choices
                label="Field type"
                values={FIELD_TYPES}
                value={fieldType}
                onChange={setFieldType}
                disabled={disabled}
              />
              {fieldType === "choice" && (
                <Field
                  label="Choices, one per line"
                  multiline
                  value={choices}
                  editable={!disabled}
                  onChangeText={setChoices}
                />
              )}
              <Text style={styles.muted}>
                Implicit views already show all fields. Selected explicit views
                gain this field; implicit stepped forms add it to their final
                step atomically.
              </Text>
              {spec.views
                .filter(
                  (v) =>
                    v.collectionId === collection.id &&
                    ["list", "table", "form", "details"].includes(v.type),
                )
                .map((v) => (
                  <Toggle
                    key={v.id}
                    label={`Include in ${v.label}`}
                    value={fieldViews.includes(v.id)}
                    disabled={disabled}
                    onChange={(value) =>
                      setFieldViews(toggled(fieldViews, v.id, value))
                    }
                  />
                ))}
              <Button
                label="Add field"
                disabled={disabled || !fieldLabel.trim()}
                onPress={() => {
                  apply({
                    type: "AddField",
                    collectionId: collection.id,
                    field: {
                      label: fieldLabel,
                      type: fieldType,
                      required: false,
                      ...(fieldType === "choice"
                        ? { choices: choices.split("\n").filter(Boolean) }
                        : {}),
                    },
                    viewIds: fieldViews,
                  });
                }}
              />
            </>
          ) : (
            <Notice text="This utility app has no collection. Use an explicit starter template or advanced declaration editing to add a schema." />
          )}
        </Card>
      )}
      {section === "views" && (
        <Card title="Views">
          {view && (
            <>
              <Choices
                label="Inspect view"
                values={spec.views.map((v) => v.id)}
                value={view.id}
                disabled={navigationDisabled}
                onChange={(next) => {
                  void inspector.transition(() => setView(next));
                }}
              />
              <Text style={styles.muted}>
                {view.type} · {view.id}
              </Text>
              <LabelInput
                identity={`view:${view.id}:label`}
                label="View label"
                value={view.label}
                disabled={disabled}
                onChange={(label) =>
                  apply({ type: "RenameLabel", targetId: view.id, label }, true)
                }
              />
              {view.collectionId && (
                <>
                  <Choices
                    label="Collection binding"
                    values={spec.collections.map((c) => c.id)}
                    value={view.collectionId}
                    onChange={(collectionId) => updateView({ collectionId })}
                    disabled={disabled}
                  />
                  <Choices
                    label="Title field"
                    values={[
                      "implicit",
                      ...(spec.collections
                        .find((c) => c.id === view.collectionId)
                        ?.fields.map((f) => f.id) ?? []),
                    ]}
                    value={view.titleFieldId ?? "implicit"}
                    disabled={disabled}
                    onChange={(id) => {
                      const next = { ...view } as unknown as Record<
                        string,
                        unknown
                      >;
                      delete next.id;
                      if (id === "implicit") delete next.titleFieldId;
                      else next.titleFieldId = id;
                      apply({
                        type: "UpdateView",
                        viewId: view.id,
                        view: next as Omit<ViewSpec, "id">,
                      });
                    }}
                  />
                  {["list", "table", "form", "details"].includes(view.type) && (
                    <View style={{ gap: 8 }}>
                      <Text style={styles.muted}>
                        Visible fields (none selected means implicit all fields)
                      </Text>
                      {(
                        spec.collections.find((c) => c.id === view.collectionId)
                          ?.fields ?? []
                      ).map((f) => (
                        <Toggle
                          key={f.id}
                          label={f.label}
                          value={view.fieldIds?.includes(f.id) ?? false}
                          disabled={disabled}
                          onChange={(value) =>
                            updateView({
                              fieldIds: toggled(
                                view.fieldIds ?? [],
                                f.id,
                                value,
                              ),
                            })
                          }
                        />
                      ))}
                    </View>
                  )}
                </>
              )}
              <Choices
                label="Presentation"
                values={["original", "compact", "cards"] as const}
                value={view.presentation ?? "original"}
                disabled={disabled}
                onChange={(value) => {
                  const next = { ...view } as unknown as Record<
                    string,
                    unknown
                  >;
                  delete next.id;
                  if (value === "original") delete next.presentation;
                  else next.presentation = value;
                  apply({
                    type: "UpdateView",
                    viewId: view.id,
                    view: next as Omit<ViewSpec, "id">,
                  });
                }}
              />
              {spec.actions
                .filter((a) => a.collectionId === view.collectionId)
                .map((a) => (
                  <Toggle
                    key={a.id}
                    label={`Offer action: ${a.label}`}
                    value={view.actionIds.includes(a.id)}
                    disabled={disabled}
                    onChange={(value) =>
                      updateView({
                        actionIds: toggled(view.actionIds, a.id, value),
                      })
                    }
                  />
                ))}
              {view.type === "richText" && (
                <LabelInput
                  identity={`view:${view.id}:markdown`}
                  label="Markdown content"
                  value={view.options?.markdown ?? ""}
                  disabled={disabled}
                  onChange={(markdown) => updateOptions({ markdown })}
                />
              )}
              {view.type === "banner" && (
                <>
                  <LabelInput
                    identity={`view:${view.id}:title`}
                    label="Banner title"
                    value={view.options?.title ?? ""}
                    disabled={disabled}
                    onChange={(title) => updateOptions({ title })}
                  />
                  <LabelInput
                    identity={`view:${view.id}:body`}
                    label="Banner body"
                    value={view.options?.body ?? ""}
                    disabled={disabled}
                    onChange={(body) => updateOptions({ body })}
                  />
                  <Choices
                    label="Tone"
                    values={
                      [
                        "neutral",
                        "accent",
                        "info",
                        "success",
                        "warning",
                      ] as const
                    }
                    value={view.options?.tone ?? "neutral"}
                    disabled={disabled}
                    onChange={(tone) => updateOptions({ tone })}
                  />
                  <Choices
                    label="Image placement"
                    values={["above", "beside"] as const}
                    value={view.options?.imagePlacement ?? "above"}
                    disabled={disabled}
                    onChange={(imagePlacement) =>
                      updateOptions({ imagePlacement })
                    }
                  />
                </>
              )}
              {(view.type === "calendar" || view.type === "timeline") && (
                <Choices
                  label="Date field"
                  values={
                    spec.collections
                      .find((c) => c.id === view.collectionId)
                      ?.fields.filter((f) => f.type === "timestamp")
                      .map((f) => f.id) ?? []
                  }
                  value={view.options?.dateFieldId ?? ""}
                  disabled={disabled}
                  onChange={(dateFieldId) => updateOptions({ dateFieldId })}
                />
              )}
              {(view.type === "imageCards" || view.type === "gallery") && (
                <Choices
                  label="Image field"
                  values={
                    spec.collections
                      .find((c) => c.id === view.collectionId)
                      ?.fields.filter((f) => f.type === "image")
                      .map((f) => f.id) ?? []
                  }
                  value={view.options?.imageFieldId ?? ""}
                  disabled={disabled}
                  onChange={(imageFieldId) => updateOptions({ imageFieldId })}
                />
              )}
              {view.type === "timer" && (
                <Field
                  label="Duration in minutes (1–180)"
                  value={String(view.options?.durationMinutes ?? 25)}
                  keyboardType="number-pad"
                  editable={!disabled}
                  onChangeText={(text) => {
                    if (/^\d+$/.test(text))
                      updateOptions({ durationMinutes: Number(text) });
                  }}
                />
              )}
              {view.type === "clock" && (
                <>
                  <Choices
                    label="Clock style"
                    values={["digital", "analog"] as const}
                    value={view.options?.style ?? "digital"}
                    disabled={disabled}
                    onChange={(style) => updateOptions({ style })}
                  />
                  <Choices
                    label="Hour format"
                    values={["system", "12", "24"] as const}
                    value={view.options?.hourFormat ?? "system"}
                    disabled={disabled}
                    onChange={(hourFormat) => updateOptions({ hourFormat })}
                  />
                  <Toggle
                    label="Show seconds"
                    value={view.options?.showSeconds ?? false}
                    disabled={disabled}
                    onChange={(showSeconds) => updateOptions({ showSeconds })}
                  />
                </>
              )}
              {view.type === "deviceControl" && (
                <Choices
                  label="Device control"
                  values={
                    [
                      "flashlight",
                      "brightness",
                      "keepAwake",
                      "haptics",
                    ] as const
                  }
                  value={view.options?.control ?? "flashlight"}
                  disabled={disabled}
                  onChange={(control) => updateOptions({ control })}
                />
              )}
              <JsonDetails
                key={`options:${view.id}`}
                label="view bindings, controls and options JSON"
                value={view}
                disabled={disabled}
                onApply={(input) => {
                  const next = { ...(input as object) } as Record<
                    string,
                    unknown
                  >;
                  delete next.id;
                  apply({
                    type: "UpdateView",
                    viewId: view.id,
                    view: next as Omit<ViewSpec, "id">,
                  });
                }}
              />
              <View style={styles.row}>
                <Button
                  label="Move view earlier"
                  variant="secondary"
                  disabled={disabled || spec.views[0].id === view.id}
                  onPress={() => {
                    const ids = spec.views.map((v) => v.id),
                      i = ids.indexOf(view.id);
                    [ids[i - 1], ids[i]] = [ids[i], ids[i - 1]];
                    apply({ type: "ReorderView", viewIds: ids });
                  }}
                />
              </View>
            </>
          )}
          <Choices
            label="New view type"
            values={VIEW_TYPES}
            value={newViewType}
            onChange={setNewViewType}
            disabled={disabled}
          />
          <Button
            label={`Add ${newViewType} view`}
            disabled={disabled}
            onPress={() =>
              apply({
                type: "AddView",
                view: defaultView(newViewType, spec, collection?.id ?? ""),
              })
            }
          />
          <Text style={styles.muted}>
            New data views bind to the selected collection. A chart, date, image
            or checklist view needs matching fields and actions; validation
            explains missing bindings.
          </Text>
        </Card>
      )}
      {section === "actions" && (
        <Card title="Actions">
          {action && (
            <>
              <Choices
                label="Inspect action"
                values={spec.actions.map((a) => a.id)}
                value={action.id}
                disabled={navigationDisabled}
                onChange={(next) => {
                  void inspector.transition(() => setAction(next));
                }}
              />
              <LabelInput
                identity={`action:${action.id}:label`}
                label="Action label"
                value={action.label}
                disabled={disabled}
                onChange={(label) =>
                  apply(
                    { type: "RenameLabel", targetId: action.id, label },
                    true,
                  )
                }
              />
              <Choices
                label="Action capability"
                values={ACTION_CAPABILITIES}
                value={action.capability}
                disabled={disabled}
                onChange={(capability) => {
                  const { id, ...definition } = action;
                  apply({
                    type: "UpdateAction",
                    actionId: id,
                    action: { ...definition, capability },
                  });
                }}
              />
              <Choices
                label="Action collection"
                values={spec.collections.map((c) => c.id)}
                value={action.collectionId}
                disabled={disabled}
                onChange={(collectionId) => {
                  const { id, ...definition } = action;
                  apply({
                    type: "UpdateAction",
                    actionId: id,
                    action: { ...definition, collectionId },
                  });
                }}
              />
              <JsonDetails
                label="action behavior binding JSON"
                value={action}
                disabled={disabled}
                onApply={(input) => {
                  const next = { ...(input as ActionSpec) };
                  delete (next as Partial<ActionSpec>).id;
                  apply({
                    type: "UpdateAction",
                    actionId: action.id,
                    action: next,
                  });
                }}
              />
            </>
          )}
          <Button
            label="Add create action"
            disabled={disabled || !collection}
            onPress={() =>
              apply({
                type: "AddAction",
                action: {
                  label: "Add record",
                  capability: "records.create.v1",
                  collectionId: collection.id,
                },
              })
            }
          />
          <Text style={styles.muted}>
            Actions are allowlisted declarations. You cannot run code or grant
            roles from this editor.
          </Text>
        </Card>
      )}
      {section === "pages" && (
        <Card title="Pages and navigation">
          {page && spec.navigation && (
            <>
              <Choices
                label="Inspect page"
                values={spec.navigation.pages.map((p) => p.id)}
                value={page.id}
                disabled={navigationDisabled}
                onChange={(next) => {
                  void inspector.transition(() => setPage(next));
                }}
              />
              <LabelInput
                identity={`page:${page.id}:title`}
                label="Page title"
                value={page.title}
                disabled={disabled}
                onChange={(label) =>
                  apply({ type: "RenameLabel", targetId: page.id, label }, true)
                }
              />
              <Choices
                label="Page layout"
                values={["stacked", "twoColumn", "featuredFirst"] as const}
                value={page.layout ?? "stacked"}
                disabled={disabled}
                onChange={(layout) => updatePage({ layout })}
              />
              <Toggle
                label="Show today’s date"
                value={page.showDate ?? false}
                disabled={disabled}
                onChange={(value) => {
                  const { id, ...next } = page;
                  if (value) next.showDate = true;
                  else delete next.showDate;
                  apply({ type: "UpdatePage", pageId: id, page: next });
                }}
              />
              {spec.views.map((v) => (
                <Toggle
                  key={v.id}
                  label={`Include ${v.label}`}
                  value={page.viewIds.includes(v.id)}
                  disabled={disabled}
                  onChange={(value) =>
                    updatePage({
                      viewIds: toggled(page.viewIds, v.id, value),
                    })
                  }
                />
              ))}
              <Choices
                label="Entry page"
                values={spec.navigation.pages.map((p) => p.id)}
                value={spec.navigation.entryPageId}
                disabled={disabled}
                onChange={(entryPageId) =>
                  apply({
                    type: "SetNavigation",
                    entryPageId,
                    tabs: spec.navigation!.tabs,
                  })
                }
              />
              <Toggle
                label="Show this page as a tab"
                value={spec.navigation.tabs.some(
                  (tab) => tab.pageId === page.id,
                )}
                disabled={disabled}
                onChange={(value) =>
                  apply({
                    type: "SetNavigation",
                    entryPageId: spec.navigation!.entryPageId,
                    tabs: value
                      ? [
                          ...spec.navigation!.tabs,
                          {
                            pageId: page.id,
                            label: page.title.slice(0, 40),
                            icon: "spark",
                          },
                        ]
                      : spec.navigation!.tabs.filter(
                          (tab) => tab.pageId !== page.id,
                        ),
                  })
                }
              />
              <Button
                label="Move page earlier"
                variant="secondary"
                disabled={disabled || spec.navigation.pages[0].id === page.id}
                onPress={() => {
                  const ids = spec.navigation!.pages.map((p) => p.id),
                    i = ids.indexOf(page.id);
                  [ids[i - 1], ids[i]] = [ids[i], ids[i - 1]];
                  apply({ type: "ReorderPages", pageIds: ids });
                }}
              />
              <JsonDetails
                label="page and primary action JSON"
                value={page}
                disabled={disabled}
                onApply={(input) => {
                  const next = { ...(input as PageSpec) };
                  delete (next as Partial<PageSpec>).id;
                  apply({ type: "UpdatePage", pageId: page.id, page: next });
                }}
              />
            </>
          )}
          <Button
            label="Add page"
            disabled={disabled || spec.views.length === 0}
            onPress={() =>
              apply({
                type: "AddPage",
                page: { title: "New page", viewIds: [spec.views[0].id] },
              })
            }
          />
        </Card>
      )}
      {section === "appearance" && (
        <Card title="Appearance">
          <LabelInput
            identity="app:name"
            label="App name"
            value={spec.name}
            disabled={disabled}
            onChange={(label) =>
              apply({ type: "RenameLabel", targetId: "app", label }, true)
            }
          />
          <Choices
            label="Theme"
            values={["teal", "amber", "blue", "rose", "sage"] as const}
            value={spec.theme}
            disabled={disabled}
            onChange={(theme) => apply({ type: "SetTheme", theme })}
          />
          <Choices
            label="App icon"
            values={["book", "board", "people", "spark", "check"] as const}
            value={spec.icon}
            disabled={disabled}
            onChange={(icon) =>
              apply({ type: "SetTheme", theme: spec.theme, icon })
            }
          />
          <Choices
            label="Style"
            values={["clean", "editorial", "playful"] as const}
            value={spec.appearance?.style ?? "clean"}
            disabled={disabled}
            onChange={(style) =>
              apply({
                type: "SetAppearance",
                appearance: { ...spec.appearance, style },
              })
            }
          />
          <Choices
            label="Typography"
            values={["sans", "serif"] as const}
            value={spec.appearance?.typography ?? "sans"}
            disabled={disabled}
            onChange={(typography) =>
              apply({
                type: "SetAppearance",
                appearance: {
                  style: spec.appearance?.style ?? "clean",
                  ...spec.appearance,
                  typography,
                },
              })
            }
          />
          <Choices
            label="Density"
            values={["compact", "comfortable", "spacious"] as const}
            value={spec.appearance?.density ?? "comfortable"}
            disabled={disabled}
            onChange={(density) =>
              apply({
                type: "SetAppearance",
                appearance: {
                  style: spec.appearance?.style ?? "clean",
                  ...spec.appearance,
                  density,
                },
              })
            }
          />
          <Choices
            label="Corners"
            values={["square", "soft", "rounded"] as const}
            value={spec.appearance?.corners ?? "soft"}
            disabled={disabled}
            onChange={(corners) =>
              apply({
                type: "SetAppearance",
                appearance: {
                  style: spec.appearance?.style ?? "clean",
                  ...spec.appearance,
                  corners,
                },
              })
            }
          />
          <LabelInput
            identity="app:accentColor"
            label="Accent color (#RRGGBB)"
            value={spec.appearance?.accentColor ?? ""}
            disabled={disabled}
            onChange={(accentColor) =>
              apply(
                {
                  type: "SetAppearance",
                  appearance: {
                    style: spec.appearance?.style ?? "clean",
                    ...spec.appearance,
                    accentColor,
                  },
                },
                true,
              )
            }
          />
          <Button
            label="Restore original appearance"
            variant="secondary"
            disabled={disabled}
            onPress={() => apply({ type: "SetAppearance", appearance: null })}
          />
          <Text style={styles.muted}>
            Displayed defaults remain absent from the declaration until you
            select a change.
          </Text>
        </Card>
      )}
      {section === "reminders" && (
        <ReminderEditor spec={spec} disabled={disabled} apply={apply} />
      )}
      {section === "JSON" && (
        <Card title="Advanced declaration">
          <Text style={styles.body}>
            This editor accepts a validated AppSpec declaration, never
            executable code. Visual controls preserve bindings; advanced changes
            still pass the same schema and publication compatibility checks.
          </Text>
          <JsonDetails
            label="full AppSpec JSON"
            value={JSON.parse(canonicalJson(spec))}
            disabled={disabled}
            onApply={onReplace}
          />
        </Card>
      )}
    </View>
  );
  return (
    <InspectorFlushContext.Provider
      value={{
        flush: () => inspector.flush(),
        resetEpoch: editorResetEpoch,
        register: inputs.register,
        accepted: () => {
          if (inputs.canFlush()) {
            errorRef.current = null;
            setError(null);
          }
        },
      }}
    >
      {content}
    </InspectorFlushContext.Provider>
  );
}
function ChoiceAdder({
  choices,
  disabled,
  onAdd,
}: {
  choices: string[];
  disabled: boolean;
  onAdd: (value: string) => void;
}) {
  const [value, setValue] = useState("");
  return (
    <>
      <Text style={styles.muted}>Choices: {choices.join(", ")}</Text>
      <Field
        label="New choice"
        value={value}
        editable={!disabled}
        onChangeText={setValue}
      />
      <Button
        label="Add choice"
        variant="secondary"
        disabled={disabled || !value.trim()}
        onPress={() => onAdd(value)}
      />
    </>
  );
}
function ReminderEditor({
  spec,
  disabled,
  apply,
}: {
  spec: AppSpec;
  disabled: boolean;
  apply: (edit: SemanticEdit, debounce?: boolean) => void;
}) {
  const [selected, setSelected] = useState("new"),
    [collectionId, setCollection] = useState(spec.collections[0]?.id ?? ""),
    [fieldId, setField] = useState(""),
    [offset, setOffset] = useState("3600"),
    [effect, setEffect] =
      useState<AutomationSpec["effect"]["type"]>("notifyOwner");
  const existing = spec.automationRequests.find((rule) => rule.id === selected);
  const collection = spec.collections.find((c) => c.id === collectionId);
  return (
    <Card title="Requested reminders">
      <Text style={styles.body}>
        Rules remain off unless selected in publication review. Publishing does
        not automatically enroll existing records. Backend worker capabilities
        determine whether an effect can be enabled.
      </Text>
      <Choices
        label="Reminder"
        values={["new", ...spec.automationRequests.map((r) => r.id)]}
        value={selected}
        onChange={(id) => {
          setSelected(id);
          const rule = spec.automationRequests.find((r) => r.id === id);
          if (rule) {
            setCollection(rule.trigger.collectionId);
            setField(rule.trigger.fieldId);
            setOffset(String(rule.trigger.offsetSeconds));
            setEffect(rule.effect.type);
          }
        }}
      />
      <Choices
        label="Collection"
        values={spec.collections.map((c) => c.id)}
        value={collectionId}
        onChange={setCollection}
        disabled={disabled}
      />
      <Choices
        label="Timestamp field"
        values={
          collection?.fields
            .filter((f) => f.type === "timestamp")
            .map((f) => f.id) ?? []
        }
        value={fieldId}
        disabled={disabled}
        onChange={setField}
      />
      <Field
        label="Seconds before timestamp"
        value={offset}
        editable={!disabled}
        keyboardType="number-pad"
        onChangeText={setOffset}
      />
      <Choices
        label="Recipients"
        values={
          ["notifyOwner", "notifyAssignee", "notifyActiveClaimants"] as const
        }
        value={effect}
        onChange={setEffect}
        disabled={disabled}
      />
      <Button
        label={existing ? "Update requested reminder" : "Propose reminder"}
        disabled={disabled || !fieldId || !/^\d+$/.test(offset)}
        onPress={() => {
          const reminder = {
            trigger: {
              type: "beforeTimestamp" as const,
              collectionId,
              fieldId,
              offsetSeconds: Number(offset),
            },
            effect: { type: effect, channel: "inApp" as const },
            ...(existing?.condition ? { condition: existing.condition } : {}),
          };
          apply(
            existing
              ? { type: "UpdateReminder", reminderId: existing.id, reminder }
              : { type: "ProposeReminder", reminder },
          );
        }}
      />
      {existing && (
        <JsonDetails
          label="reminder condition JSON"
          value={existing}
          disabled={disabled}
          onApply={(input) => {
            const next = { ...(input as AutomationSpec) };
            delete (next as Partial<AutomationSpec>).id;
            apply({
              type: "UpdateReminder",
              reminderId: existing.id,
              reminder: next,
            });
          }}
        />
      )}
    </Card>
  );
}
