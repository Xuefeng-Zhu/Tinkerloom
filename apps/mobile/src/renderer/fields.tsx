import { useEffect, useState, useRef } from "react";
import { Image, Pressable, Switch, Text, View } from "react-native";
import type { FieldSpec, FormControl } from "../spec/types";
import type {
  ImageAsset,
  RuntimeAdapter,
  RuntimeMember,
  RuntimeRecord,
  ReminderState,
} from "../runtime/types";
import { useRuntime } from "./context";
import { Body, Button, Input, Notice, Row } from "./primitives";
import { displayField } from "./model";

export function PrivateImage({
  assetId,
  alt = "Private image",
}: {
  assetId: string;
  alt?: string;
}) {
  const { controller } = useRuntime(),
    adapter = controller.adapter;
  const [response, setResponse] = useState<{
    scope: RuntimeAdapter;
    id: string;
    asset?: ImageAsset;
    error?: string;
  } | null>(null);
  const state =
    response?.scope === adapter && response.id === assetId ? response : null;
  useEffect(() => {
    let active = true;
    if (!adapter.features.has("imageRead")) return;
    adapter.readImage(assetId).then(
      (asset) => {
        if (active) setResponse({ scope: adapter, id: assetId, asset });
      },
      () => {
        if (active)
          setResponse({
            scope: adapter,
            id: assetId,
            error: "This private image could not be loaded.",
          });
      },
    );
    return () => {
      active = false;
    };
  }, [adapter, assetId]);
  if (!adapter.features.has("imageRead"))
    return <Notice>Private images are unavailable in this runtime.</Notice>;
  if (state?.error) return <Notice>{state.error}</Notice>;
  if (!state?.asset) return <Body muted>Loading image…</Body>;
  return (
    <Image
      source={{ uri: state.asset.uri }}
      accessibilityLabel={alt}
      accessible
      resizeMode="cover"
      style={{ width: "100%", height: 200, borderRadius: 8 }}
    />
  );
}
export function FieldValue({
  field,
  value,
}: {
  field: FieldSpec;
  value: unknown;
}) {
  return field.type === "image" && typeof value === "string" ? (
    <PrivateImage assetId={value} alt={field.label} />
  ) : (
    <View>
      <Body muted>{field.label}</Body>
      <Body>{displayField(field, value)}</Body>
    </View>
  );
}
export function RecordReminder({ record }: { record: RuntimeRecord }) {
  const { controller } = useRuntime(),
    adapter = controller.adapter,
    requested = adapter.spec.automationRequests.some(
      (rule) => rule.trigger.collectionId === record.collectionId,
    ),
    [response, setResponse] = useState<{
      adapter: RuntimeAdapter;
      id: string;
      revision: number;
      state?: ReminderState;
      error?: string;
    } | null>(null),
    current =
      response?.adapter === adapter &&
      response.id === record.id &&
      response.revision === record.revision
        ? response
        : null;
  useEffect(() => {
    let active = true;
    if (!requested || !adapter.features.has("reminders")) return;
    adapter.reminderState(record.id).then(
      (state) => {
        if (active)
          setResponse({
            adapter,
            id: record.id,
            revision: record.revision,
            state,
          });
      },
      () => {
        if (active)
          setResponse({
            adapter,
            id: record.id,
            revision: record.revision,
            error: "Reminder status could not be loaded.",
          });
      },
    );
    return () => {
      active = false;
    };
  }, [adapter, requested, record.id, record.revision]);
  if (!requested) return null;
  if (!adapter.features.has("reminders"))
    return (
      <Body muted>
        Live reminder status is unavailable. A definition request does not
        enable a reminder worker.
      </Body>
    );
  return (
    <Body muted>
      {current?.state?.label ?? current?.error ?? "Loading reminder status…"}
    </Body>
  );
}
interface FieldInputProps {
  field: FieldSpec;
  value: string | boolean | null;
  onChange: (value: string | boolean | null) => void;
  control?: FormControl;
  disabled?: boolean;
  members: readonly RuntimeMember[];
  onBusyChange?: (busy: boolean) => void;
  uploadContext?: import("../runtime/types").RuntimeImageUploadContext;
}
export function FieldInput({
  field,
  value,
  onChange,
  control,
  disabled = false,
  members,
  onBusyChange,
  uploadContext,
}: FieldInputProps) {
  const { controller, theme } = useRuntime(),
    [uploading, setUploading] = useState(false),
    [error, setError] = useState<string | null>(null),
    [trackWidth, setTrackWidth] = useState(1);
  const lifetime = useRef<{ active: boolean } | null>(null);
  useEffect(() => {
    const current = { active: true };
    lifetime.current = current;
    return () => {
      current.active = false;
    };
  }, [
    controller.adapter,
    field.id,
    uploadContext?.versionId,
    uploadContext?.actionId,
    uploadContext?.fieldId,
    uploadContext?.targetRecordId,
    uploadContext?.expectedRecordRevision,
  ]);
  const kind =
    control?.control ??
    (field.type === "boolean"
      ? "switch"
      : field.type === "choice" || field.type === "member"
        ? "select"
        : field.type === "timestamp"
          ? "dateTime"
          : field.type === "image"
            ? "imageUpload"
            : "text");
  const choices =
    field.type === "choice"
      ? field.choices!.map((label) => ({ id: label, label }))
      : members;
  const number =
      typeof value === "string" && value.trim() ? Number(value) : NaN,
    min = kind === "rating" ? 1 : (control?.min ?? 0),
    max = kind === "rating" ? 5 : (control?.max ?? 100),
    step = control?.step ?? 1;
  const changeNumber = (candidate: number) =>
    onChange(
      String(Math.round(Math.min(max, Math.max(min, candidate)) * 1e9) / 1e9),
    );
  const chooseImage = async () => {
    const active = lifetime.current;
    if (!active?.active) return;
    setError(null);
    setUploading(true);
    onBusyChange?.(true);
    try {
      const picked = await controller.adapter.pickImage();
      if (!active.active) return;
      if (picked) {
        const assetId = await controller.adapter.uploadImage(
          picked,
          uploadContext,
        );
        if (active.active) onChange(assetId);
      }
    } catch {
      if (active.active)
        setError(
          "The image could not be uploaded. Your other values are retained.",
        );
    } finally {
      if (active.active) {
        setUploading(false);
        onBusyChange?.(false);
      }
    }
  };
  let input;
  if (field.type === "boolean")
    input =
      kind === "checkbox" ? (
        <Pressable
          accessibilityRole="checkbox"
          accessibilityLabel={field.label}
          accessibilityState={{ checked: value === true, disabled }}
          disabled={disabled}
          onPress={() => onChange(value !== true)}
          style={{ minHeight: 48, justifyContent: "center" }}
        >
          <Body>
            {value === true ? "☑" : "☐"}{" "}
            {value === null ? "Not set" : value ? "Yes" : "No"}
          </Body>
        </Pressable>
      ) : (
        <Row>
          <Switch
            accessibilityLabel={field.label}
            value={value === true}
            disabled={disabled}
            onValueChange={onChange}
          />
          <Body>{value === null ? "Not set" : value ? "Yes" : "No"}</Body>
        </Row>
      );
  else if (field.type === "choice" || field.type === "member")
    input = (
      <Row>
        {choices.map((choice) => (
          <Button
            key={choice.id}
            subtle
            selected={value === choice.id}
            disabled={disabled}
            onPress={() => onChange(choice.id)}
          >
            {choice.label}
          </Button>
        ))}
        {field.type === "member" && !choices.length ? (
          <Body muted>Member selection is unavailable.</Body>
        ) : null}
      </Row>
    );
  else if (field.type === "image")
    input = (
      <View style={{ gap: 8 }}>
        {typeof value === "string" && value ? (
          <PrivateImage assetId={value} alt={field.label} />
        ) : null}
        {controller.adapter.preview ? (
          <Button
            disabled={disabled}
            onPress={() => onChange("preview_image_0")}
          >
            Use example image
          </Button>
        ) : (
          <Button
            disabled={
              disabled ||
              uploading ||
              !controller.adapter.features.has("imageUpload")
            }
            onPress={() => void chooseImage()}
          >
            {uploading ? "Uploading…" : "Choose image"}
          </Button>
        )}
        {!controller.adapter.preview &&
        !controller.adapter.features.has("imageUpload") ? (
          <Notice>Private image uploads are not available yet.</Notice>
        ) : null}
      </View>
    );
  else if (kind === "rating")
    input = (
      <View style={{ gap: 6 }}>
        <Row>
          {[1, 2, 3, 4, 5].map((rating) => (
            <Button
              key={rating}
              label={`${field.label}: ${rating} of 5`}
              selected={number === rating}
              subtle
              disabled={disabled}
              onPress={() => onChange(String(rating))}
            >
              {rating <= number ? "★" : "☆"} {rating}
            </Button>
          ))}
        </Row>
        <Body muted>Current value: {value ?? "Not set"}</Body>
      </View>
    );
  else if (kind === "slider" || kind === "stepper")
    input = (
      <View style={{ gap: 8 }}>
        {kind === "slider" ? (
          <Pressable
            disabled={disabled}
            onLayout={(event) => setTrackWidth(event.nativeEvent.layout.width)}
            onPress={(event) =>
              changeNumber(
                min +
                  Math.round(
                    ((event.nativeEvent.locationX / trackWidth) * (max - min)) /
                      step,
                  ) *
                    step,
              )
            }
            accessible
            accessibilityRole="adjustable"
            accessibilityLabel={field.label}
            accessibilityValue={{
              min,
              max,
              ...(Number.isFinite(number) ? { now: number } : {}),
              text: value === null ? "Not set" : String(value),
            }}
            accessibilityActions={[
              { name: "increment" },
              { name: "decrement" },
            ]}
            onAccessibilityAction={(event) => {
              if (!disabled)
                changeNumber(
                  (Number.isFinite(number) ? number : min) +
                    (event.nativeEvent.actionName === "increment"
                      ? step
                      : -step),
                );
            }}
            style={{ height: 44, justifyContent: "center" }}
          >
            <View
              style={{
                height: 8,
                backgroundColor: theme.outline,
                borderRadius: 4,
              }}
            >
              <View
                style={{
                  height: 8,
                  width: `${Number.isFinite(number) ? Math.max(0, Math.min(100, ((number - min) / (max - min)) * 100)) : 0}%`,
                  backgroundColor: theme.accent,
                  borderRadius: 4,
                }}
              />
            </View>
          </Pressable>
        ) : null}
        <Row>
          <Button
            label={`Decrease ${field.label}`}
            disabled={disabled}
            subtle
            onPress={() =>
              changeNumber((Number.isFinite(number) ? number : min) - step)
            }
          >
            −
          </Button>
          <View style={{ minWidth: 90, flex: 1 }}>
            <Input
              accessibilityLabel={field.label}
              value={typeof value === "string" ? value : ""}
              keyboardType="numbers-and-punctuation"
              editable={!disabled}
              onChangeText={onChange}
            />
          </View>
          <Button
            label={`Increase ${field.label}`}
            disabled={disabled}
            subtle
            onPress={() =>
              changeNumber((Number.isFinite(number) ? number : min) + step)
            }
          >
            +
          </Button>
        </Row>
        <Body muted>
          {min}–{max}; step {step}. A stored value outside this range is
          retained until you change it.
        </Body>
      </View>
    );
  else
    input = (
      <Input
        accessibilityLabel={field.label}
        value={typeof value === "string" ? value : ""}
        onChangeText={onChange}
        editable={!disabled}
        multiline={kind === "multiline"}
        style={
          kind === "multiline"
            ? { minHeight: 120, textAlignVertical: "top" }
            : undefined
        }
        keyboardType={
          field.type === "integer" || field.type === "number"
            ? "numbers-and-punctuation"
            : "default"
        }
        autoCapitalize={field.type === "timestamp" ? "none" : "sentences"}
        placeholder={
          field.type === "timestamp" ? "2030-01-05T10:00:00Z" : undefined
        }
      />
    );
  return (
    <View style={{ gap: 6 }}>
      <Text style={{ fontSize: 16, fontWeight: "600", color: theme.ink }}>
        {field.label}
        {field.required ? " *" : " (optional)"}
      </Text>
      {input}
      {control?.hint ? <Body muted>{control.hint}</Body> : null}
      {field.type === "timestamp" ? (
        <Body muted>
          Enter an ISO date and time with Z or an explicit offset. Stored values
          keep their full precision.
        </Body>
      ) : null}
      {!field.required && value !== null && value !== "" ? (
        <Button subtle disabled={disabled} onPress={() => onChange(null)}>
          Clear {field.label}
        </Button>
      ) : null}
      {error ? <Notice error>{error}</Notice> : null}
    </View>
  );
}
