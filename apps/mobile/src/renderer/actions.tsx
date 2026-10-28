import { ownValue } from "../spec/ownValue";
import { useEffect, useState } from "react";
import { View } from "react-native";
import { getCollection, getField } from "../spec/bindings";
import type { ActionSpec, JsonValue, ViewSpec } from "../spec/types";
import type { RuntimeMember, RuntimeRecord } from "../runtime/types";
import { useRuntime } from "./context";
import { Body, Button, Input, Notice, Row } from "./primitives";
import { transitionTargets } from "./model";

export function ActionControl({
  action,
  view,
  record,
}: {
  action: ActionSpec;
  view: ViewSpec;
  record?: RuntimeRecord;
}) {
  const { controller, state, edit } = useRuntime(),
    adapter = controller.adapter,
    [expanded, setExpanded] = useState(false),
    [amount, setAmount] = useState(String(record?.capacity ?? 1)),
    [members, setMembers] = useState<RuntimeMember[]>([]),
    [error, setError] = useState<string | null>(null),
    allowed = adapter.permits(action, record),
    disabled = !allowed || !controller.writeAvailable || Boolean(state.pending);
  useEffect(() => {
    let active = true;
    if (expanded && action.capability === "assignment.assign.v1")
      adapter.members().then(
        (rows) => {
          if (active) setMembers(rows);
        },
        () => {
          if (active) setError("The member directory could not be loaded.");
        },
      );
    return () => {
      active = false;
    };
  }, [adapter, action.capability, expanded]);
  const execute = async (input: Record<string, JsonValue>) => {
    setError(null);
    try {
      const result = await controller.execute(action.id, input, record);
      if (result) setExpanded(false);
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "This action could not be completed.",
      );
    }
  };
  if (action.capability === "records.create.v1")
    return (
      <Button disabled={disabled} onPress={() => edit(view)}>
        {action.label}
      </Button>
    );
  if (!record) return null;
  if (action.capability === "records.patch.v1")
    return (
      <Button subtle disabled={disabled} onPress={() => edit(view, record)}>
        {action.label}
      </Button>
    );
  if (action.capability === "workflow.transition.v1") {
    const targets = transitionTargets(adapter.spec, action.id, record);
    return (
      <View style={{ gap: 6 }}>
        <Body muted>{action.label}</Body>
        <Row>
          {targets.map((value) => (
            <Button
              key={value}
              subtle
              disabled={disabled}
              onPress={() => void execute({ value })}
            >
              {value}
            </Button>
          ))}
          {!targets.length ? <Body muted>No next transition</Body> : null}
        </Row>
        {error ? <Notice error>{error}</Notice> : null}
      </View>
    );
  }
  if (
    action.capability === "capacity.claim.v1" ||
    action.capability === "capacity.release.v1"
  ) {
    const claim = action.capability === "capacity.claim.v1";
    return (
      <View style={{ gap: 6 }}>
        <Button
          subtle
          disabled={
            disabled ||
            (claim
              ? record.claimed || record.allocated === record.capacity
              : !record.claimed)
          }
          onPress={() => void execute({})}
        >
          {record.claimed && claim ? "You have signed up" : action.label}
        </Button>
        {error ? <Notice error>{error}</Notice> : null}
      </View>
    );
  }
  const collection = getCollection(adapter.spec, action.collectionId),
    behavior = collection.behaviors.find((b) => b.id === action.behaviorId),
    field = behavior?.fieldId ? getField(collection, behavior.fieldId) : null;
  return (
    <View style={{ gap: 8 }}>
      <Button
        subtle
        disabled={disabled}
        onPress={() => setExpanded((value) => !value)}
      >
        {action.label}
      </Button>
      {expanded && action.capability === "assignment.assign.v1" ? (
        <Row>
          {members.map((member) => (
            <Button
              key={member.id}
              subtle
              disabled={disabled}
              selected={ownValue(record.data, field!.id) === member.id}
              onPress={() => void execute({ value: member.id })}
            >
              {member.label}
            </Button>
          ))}
          {field && !field.required ? (
            <Button
              subtle
              disabled={disabled}
              onPress={() => void execute({ value: null })}
            >
              Unassign
            </Button>
          ) : null}
        </Row>
      ) : null}
      {expanded && action.capability === "capacity.configure.v1" ? (
        <Row>
          <Input
            accessibilityLabel="New capacity"
            value={amount}
            onChangeText={setAmount}
            keyboardType="number-pad"
            editable={!disabled}
          />
          <Button
            disabled={disabled}
            onPress={() => {
              if (!/^\d+$/.test(amount) || Number(amount) > 10000) {
                setError("Capacity must be between 0 and 10,000.");
                return;
              }
              void execute({ capacity: Number(amount) });
            }}
          >
            Set capacity
          </Button>
        </Row>
      ) : null}
      {error ? <Notice error>{error}</Notice> : null}
    </View>
  );
}
export function ViewActions({
  view,
  record,
  createOnly = false,
}: {
  view: ViewSpec;
  record?: RuntimeRecord;
  createOnly?: boolean;
}) {
  const { controller } = useRuntime();
  return (
    <Row>
      {view.actionIds
        .map((id) => controller.adapter.spec.actions.find((a) => a.id === id)!)
        .filter((action) =>
          createOnly
            ? action.capability === "records.create.v1"
            : action.capability !== "records.create.v1",
        )
        .map((action) => (
          <ActionControl
            key={action.id}
            action={action}
            view={view}
            record={record}
          />
        ))}
    </Row>
  );
}
