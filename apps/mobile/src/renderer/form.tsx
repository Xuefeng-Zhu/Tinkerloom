import { useEffect, useState } from "react";
import { View } from "react-native";
import type { ViewSpecOf } from "../spec/types";
import type { RuntimeMember, RuntimeRecord } from "../runtime/types";
import { getCollection } from "../spec/bindings";
import { useRuntime } from "./context";
import { Body, Button, Notice, Row, Input } from "./primitives";
import { FieldInput } from "./fields";
import {
  editorFields,
  initialEditorValues,
  normalizedEditorData,
} from "./model";

export function RecordForm({
  view,
  record,
  onSaved,
  onCancel,
}: {
  view: ViewSpecOf<"form">;
  record?: RuntimeRecord;
  onSaved?: () => void;
  onCancel?: () => void;
}) {
  const { controller, state } = useRuntime(),
    adapter = controller.adapter,
    spec = adapter.spec;
  const fields = editorFields(spec, view, record),
    [values, setValues] = useState(() => initialEditorValues(fields, record)),
    [capacity, setCapacity] = useState(String(record?.capacity ?? 1)),
    [step, setStep] = useState(0),
    [members, setMembers] = useState<RuntimeMember[]>([]),
    [uploads, setUploads] = useState<Record<string, boolean>>({}),
    [error, setError] = useState<string | null>(null);
  const collection = getCollection(spec, view.collectionId),
    hasCapacity = collection.behaviors.some((b) => b.type === "capacity.v1"),
    steps = view.options?.steps ?? [],
    visible = steps.length
      ? fields.filter((f) => steps[step].fieldIds.includes(f.id))
      : fields;
  const action = spec.actions.find(
    (a) =>
      a.collectionId === view.collectionId &&
      a.capability === (record ? "records.patch.v1" : "records.create.v1") &&
      view.actionIds.includes(a.id),
  );
  const disabled =
    Boolean(state.pending) ||
    Object.values(uploads).some(Boolean) ||
    !controller.writeAvailable ||
    !action ||
    !adapter.permits(action, record);
  const needsMembers = fields.some((field) => field.type === "member");
  useEffect(() => {
    let active = true;
    if (needsMembers) {
      adapter.members().then(
        (rows) => {
          if (active) setMembers(rows);
        },
        () => {
          if (active)
            setError("The eligible member directory could not be loaded.");
        },
      );
    }
    return () => {
      active = false;
    };
  }, [adapter, needsMembers]);
  const change = (id: string, value: string | boolean | null) => {
    setValues((previous) => ({ ...previous, [id]: value }));
    controller.setDirty(true);
    setError(null);
  };
  const next = () => {
    try {
      normalizedEditorData(visible, values, view.options?.controls, record);
      setStep((index) => index + 1);
      setError(null);
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "Review the values in this step.",
      );
    }
  };
  const save = async () => {
    try {
      setError(null);
      if (!action) throw new Error("This form has no permitted save action.");
      const data = normalizedEditorData(
        fields,
        values,
        view.options?.controls,
        record,
      );
      if (!record)
        for (const behavior of collection.behaviors)
          if (behavior.type === "workflow.v1")
            data[behavior.fieldId!] = collection.fields.find(
              (field) => field.id === behavior.fieldId,
            )!.choices![0];
      let amount: number | undefined;
      if (hasCapacity && !record) {
        if (
          !/^\d+$/.test(capacity) ||
          !Number.isInteger(Number(capacity)) ||
          Number(capacity) > 10000
        )
          throw new Error("Capacity must be between 0 and 10,000.");
        amount = Number(capacity);
      }
      const outcome = await controller.execute(
        action.id,
        { data, ...(amount === undefined ? {} : { capacity: amount }) },
        record,
      );
      if (outcome) {
        if (!record) {
          setValues(initialEditorValues(fields));
          setStep(0);
        }
        onSaved?.();
      }
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "Your changes could not be saved.",
      );
    }
  };
  return (
    <View style={{ gap: 18 }}>
      {record ? (
        <Body muted>
          Editing revision {record.revision}. The record and published
          definition are retained together until this command resolves.
        </Body>
      ) : null}
      {steps.length ? (
        <View>
          <Body muted>
            Step {step + 1} of {steps.length}
          </Body>
          <Body heading>{steps[step].title}</Body>
        </View>
      ) : null}
      {visible.map((field) => (
        <FieldInput
          key={field.id}
          field={field}
          value={values[field.id] ?? null}
          onChange={(value) => change(field.id, value)}
          control={view.options?.controls?.find((c) => c.fieldId === field.id)}
          members={members}
          onBusyChange={(busy) =>
            setUploads((previous) => ({ ...previous, [field.id]: busy }))
          }
          disabled={disabled}
        />
      ))}
      {hasCapacity &&
      !record &&
      (!steps.length || step === steps.length - 1) ? (
        <View style={{ gap: 6 }}>
          <Body>Capacity</Body>
          <Input
            accessibilityLabel="Capacity"
            value={capacity}
            onChangeText={(value) => {
              setCapacity(value);
              controller.setDirty(true);
            }}
            keyboardType="number-pad"
            editable={!disabled}
          />
        </View>
      ) : null}
      {error ? <Notice error>{error}</Notice> : null}
      {!action ? (
        <Notice>No save action is configured for this form.</Notice>
      ) : null}
      {action && !adapter.permits(action, record) ? (
        <Notice>This app is read only for your current role.</Notice>
      ) : null}
      <Row>
        {step > 0 ? (
          <Button
            subtle
            disabled={Boolean(state.pending)}
            onPress={() => setStep((index) => index - 1)}
          >
            Previous
          </Button>
        ) : null}
        {steps.length && step < steps.length - 1 ? (
          <Button disabled={disabled} onPress={next}>
            Next
          </Button>
        ) : (
          <Button disabled={disabled} onPress={() => void save()}>
            {state.pending?.status === "sending"
              ? "Saving…"
              : record
                ? "Save changes"
                : "Create record"}
          </Button>
        )}
        {onCancel ? (
          <Button subtle disabled={Boolean(state.pending)} onPress={onCancel}>
            Cancel
          </Button>
        ) : null}
      </Row>
    </View>
  );
}
