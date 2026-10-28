import { useState } from "react";
import type { ReactNode } from "react";
import { Animated, PanResponder, Text, View } from "react-native";
import type { ViewSpecOf } from "../spec/types";
import type { RuntimeRecord } from "../runtime/types";
import { useRuntime } from "./context";
import { Notice } from "./primitives";
import { transitionTargets } from "./model";

export function DraggableBoardRecord({
  view,
  record,
  dropTarget,
  children,
}: {
  view: ViewSpecOf<"board">;
  record: RuntimeRecord;
  dropTarget: (x: number, y: number) => Promise<string | null>;
  children: ReactNode;
}) {
  const { controller, state, theme } = useRuntime(),
    [position] = useState(() => new Animated.ValueXY()),
    [dragging, setDragging] = useState(false),
    [error, setError] = useState<string | null>(null),
    [base, setBase] = useState(record),
    action = controller.adapter.spec.actions.find(
      (a) => a.id === view.options?.moveActionId,
    ),
    enabled = Boolean(
      view.options?.draggable &&
      action &&
      controller.writeAvailable &&
      !state.pending &&
      !state.dirty &&
      controller.adapter.permits(action, record),
    );
  const stop = () => {
    position.setValue({ x: 0, y: 0 });
    setDragging(false);
  };
  const responder = PanResponder.create({
    onStartShouldSetPanResponder: () => enabled,
    onMoveShouldSetPanResponder: () => enabled,
    onPanResponderGrant: () => {
      setBase(record);
      setError(null);
      setDragging(true);
    },
    onPanResponderMove: (_event, gesture) =>
      position.setValue({ x: gesture.dx, y: gesture.dy }),
    onPanResponderTerminationRequest: () => true,
    onPanResponderTerminate: stop,
    onPanResponderRelease: (_event, gesture) => {
      stop();
      void (async () => {
        try {
          const location = controller.getSnapshot().location;
          const target = await dropTarget(gesture.moveX, gesture.moveY);
          if (controller.getSnapshot().location !== location) return;
          if (!target || !action) return;
          const original = base;
          if (
            !transitionTargets(
              controller.adapter.spec,
              action.id,
              original,
            ).includes(target)
          ) {
            setError(
              "That column is not an allowed next state. No change was sent.",
            );
            return;
          }
          await controller.execute(action.id, { value: target }, original);
        } catch {
          setError(
            "This move could not be completed. The original record revision is retained.",
          );
        }
      })();
    },
  });
  return (
    <Animated.View
      style={{
        transform: position.getTranslateTransform(),
        zIndex: dragging ? 10 : 0,
        gap: 6,
        opacity: dragging ? 0.85 : 1,
      }}
    >
      {enabled ? (
        <View
          {...responder.panHandlers}
          accessible
          accessibilityRole="text"
          accessibilityLabel="Drag handle. Transition buttons below provide the same action without dragging."
          style={{
            minHeight: 44,
            padding: 10,
            backgroundColor: theme.canvas,
            borderRadius: 6,
          }}
        >
          <Text style={{ color: theme.muted }}>
            ⠿ Drag to an allowed column
          </Text>
        </View>
      ) : null}
      {children}
      {error ? <Notice error>{error}</Notice> : null}
    </Animated.View>
  );
}
