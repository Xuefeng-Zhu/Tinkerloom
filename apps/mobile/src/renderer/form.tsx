import { ownValue } from "../spec/ownValue";
import { useEffect, useState, useRef, useId } from "react";
import { View, Text, Platform, AccessibilityInfo } from "react-native";
import type { ViewSpecOf } from "../spec/types";
import type { RuntimeMember, RuntimeRecord } from "../runtime/types";
import { getCollection } from "../spec/bindings";
import { useRuntime } from "./context";
import { Body, Button, Notice, Row, Input } from "./primitives";
import { FieldInput } from "./fields";
import type { FieldFocusHandle } from "./fields";
import {
  editorFields,
  initialEditorValues,
  editorValidation,
  firstEditorIssueTarget,
  FieldValidationError,
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
    [error, setError] = useState<string | null>(null),
    [fieldErrors, setFieldErrors] = useState<ReadonlyMap<string, string>>(
      () => new Map(),
    ),
    [focusRequest, setFocusRequest] = useState<{
      fieldId: string;
      label: string;
      detail: string;
      step: number;
      serial: number;
    } | null>(null);
  const formId = useId(),
    focusTargets = useRef(new Map<string, FieldFocusHandle>()),
    focusSerial = useRef(0),
    focusedSerial = useRef(0);
  const capacityId = "__capacity";
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
    state.formBusy ||
    !controller.writeAvailable ||
    !action ||
    !adapter.permits(action, record);
  useEffect(() => {
    if (!focusRequest || focusedSerial.current === focusRequest.serial) return;
    focusedSerial.current = focusRequest.serial;
    if (!disabled && !state.pending) {
      focusTargets.current.get(focusRequest.fieldId)?.focus();
      if (Platform.OS !== "web")
        AccessibilityInfo.announceForAccessibility(
          `${focusRequest.label}. ${focusRequest.detail}`,
        );
    }
    setFocusRequest(null);
  }, [focusRequest, disabled, state.pending]);
  const applyIssues = (issues: readonly FieldValidationError[]) => {
    setFieldErrors(
      new Map(issues.map((issue) => [issue.fieldId, issue.detail])),
    );
    const target = firstEditorIssueTarget(
      issues,
      steps,
      Math.max(0, steps.length - 1),
    );
    setError(null);
    if (!target) {
      setFocusRequest(null);
      return false;
    }
    setStep(target.step);
    setFocusRequest({ ...target, serial: ++focusSerial.current });
    return true;
  };
  const registerTarget = (id: string, target: FieldFocusHandle | null) => {
    if (target) focusTargets.current.set(id, target);
    else focusTargets.current.delete(id);
  };
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
    setFocusRequest(null);
    controller.setDirty(true);
    setFieldErrors((previous) => {
      const next = new Map(previous);
      next.delete(id);
      return next;
    });
    setError(null);
  };
  const next = () => {
    if (disabled || state.pending) return;
    const validation = editorValidation(
      visible,
      values,
      view.options?.controls,
      record,
    );
    if (applyIssues(validation.issues)) return;
    setStep((index) => index + 1);
  };
  const save = async () => {
    if (disabled || state.pending) return;
    if (!action) {
      setError("This form has no permitted save action.");
      return;
    }
    const validation = editorValidation(
      fields,
      values,
      view.options?.controls,
      record,
    );
    if (applyIssues(validation.issues)) return;
    const data = validation.data;
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
      ) {
        applyIssues([
          new FieldValidationError(
            capacityId,
            "Capacity",
            "Enter a whole number between 0 and 10,000.",
          ),
        ]);
        return;
      }
      amount = Number(capacity);
    }
    // Backend outcomes are handled separately from local validation: no late
    // response can move the user's focus or discard their controlled values.
    try {
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
          ref={(target) => registerTarget(field.id, target)}
          validationError={fieldErrors.get(field.id)}
          errorId={`${formId}-${field.id}-error`}
          field={field}
          value={ownValue(values, field.id) ?? null}
          onChange={(value) => change(field.id, value)}
          control={view.options?.controls?.find((c) => c.fieldId === field.id)}
          members={members}
          uploadContext={
            action
              ? {
                  versionId: adapter.versionId,
                  actionId: action.id,
                  fieldId: field.id,
                  ...(record
                    ? {
                        targetRecordId: record.id,
                        expectedRecordRevision: record.revision,
                      }
                    : {}),
                }
              : undefined
          }
          onBusyStart={() => controller.beginFormInteraction()}
          disabled={disabled}
        />
      ))}
      {hasCapacity &&
      !record &&
      (!steps.length || step === steps.length - 1) ? (
        <View style={{ gap: 6 }}>
          <Body>Capacity</Body>
          <Input
            ref={(target) => registerTarget(capacityId, target)}
            invalid={fieldErrors.has(capacityId)}
            errorId={`${formId}-capacity-error`}
            accessibilityHint={fieldErrors.get(capacityId)}
            accessibilityLabel="Capacity"
            value={capacity}
            onChangeText={(value) => {
              setCapacity(value);
              setFocusRequest(null);
              controller.setDirty(true);
              setFieldErrors((previous) => {
                const next = new Map(previous);
                next.delete(capacityId);
                return next;
              });
              setError(null);
            }}
            keyboardType="number-pad"
            editable={!disabled}
          />
          {fieldErrors.has(capacityId) ? (
            <Text
              nativeID={`${formId}-capacity-error`}
              accessibilityRole="alert"
              accessibilityLiveRegion="polite"
              style={{ color: "#b42318" }}
            >
              {fieldErrors.get(capacityId)}
            </Text>
          ) : null}
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
            disabled={Boolean(state.pending) || state.formBusy}
            onPress={() => {
              setFocusRequest(null);
              setStep((index) => index - 1);
            }}
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
          <Button
            subtle
            disabled={Boolean(state.pending) || state.formBusy}
            onPress={onCancel}
          >
            Cancel
          </Button>
        ) : null}
      </Row>
    </View>
  );
}
