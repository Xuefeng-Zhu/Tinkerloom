import { useEffect, useState, useSyncExternalStore } from "react";
import { Text, View } from "react-native";
import {
  clockOptions,
  deviceFieldCapability,
  timerOptions,
} from "../spec/bindings";
import type { ViewSpecOf } from "../spec/types";
import type { DeviceState, DeviceBridge } from "../runtime/types";
import { phaseAt, remainingAt } from "../runtime/timer";
import { useRuntime } from "./context";
import { Body, Button, Input, Notice, Row } from "./primitives";

function useNow() {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const tick = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(tick);
  }, []);
  return now;
}
export function ClockView({ view }: { view: ViewSpecOf<"clock"> }) {
  const now = useNow(),
    options = clockOptions(view),
    { theme } = useRuntime();
  const time = now.toLocaleTimeString(undefined, {
    hour: "2-digit",
    minute: "2-digit",
    ...(options.showSeconds ? { second: "2-digit" } : {}),
    ...(options.hourFormat === "system"
      ? {}
      : { hour12: options.hourFormat === "12" }),
  });
  const hands = [
    {
      rotation: (now.getHours() % 12) * 30 + now.getMinutes() / 2,
      height: 48,
      width: 5,
    },
    {
      rotation: now.getMinutes() * 6 + now.getSeconds() / 10,
      height: 68,
      width: 3,
    },
    ...(options.showSeconds
      ? [{ rotation: now.getSeconds() * 6, height: 75, width: 1 }]
      : []),
  ];
  return (
    <View style={{ gap: 12, alignItems: "center" }}>
      {options.style === "analog" ? (
        <View
          accessible
          accessibilityLabel={time}
          style={{
            width: 190,
            height: 190,
            borderRadius: 95,
            borderWidth: 2,
            borderColor: theme.ink,
            position: "relative",
          }}
        >
          {[
            { n: "12", top: 7, left: 83 },
            { n: "3", top: 81, left: 166 },
            { n: "6", top: 155, left: 88 },
            { n: "9", top: 81, left: 9 },
          ].map((mark) => (
            <Text
              key={mark.n}
              style={{
                position: "absolute",
                top: mark.top,
                left: mark.left,
                color: theme.ink,
                fontSize: 16,
              }}
            >
              {mark.n}
            </Text>
          ))}
          {hands.map((hand, index) => (
            <View
              key={index}
              style={{
                position: "absolute",
                left: 92,
                top: 16,
                width: hand.width,
                height: 154,
                transform: [{ rotate: `${hand.rotation}deg` }],
              }}
            >
              <View style={{ height: 77 - hand.height }} />
              <View
                style={{
                  height: hand.height,
                  width: hand.width,
                  backgroundColor: index === 2 ? theme.accent : theme.ink,
                  borderRadius: 3,
                }}
              />
            </View>
          ))}
        </View>
      ) : (
        <Text
          accessibilityLabel={`Time ${time}`}
          style={{
            fontSize: 44,
            color: theme.ink,
            fontVariant: ["tabular-nums"],
          }}
        >
          {time}
        </Text>
      )}
      {options.showDate ? (
        <Body>
          {now.toLocaleDateString(undefined, {
            weekday: "long",
            year: "numeric",
            month: "long",
            day: "numeric",
          })}
        </Body>
      ) : null}
    </View>
  );
}
const noSubscribe = () => () => {};
const noState = () => undefined;
export function TimerView({ view }: { view: ViewSpecOf<"timer"> }) {
  const { timers, controller } = useRuntime(),
    minutes = timerOptions(view).durationMinutes,
    now = useNow(),
    [error, setError] = useState<string | null>(null);
  const state = useSyncExternalStore(
    timers?.subscribe ?? noSubscribe,
    () => timers?.stateFor(view.id),
    noState,
  );
  const available = Boolean(
    timers &&
    (controller.adapter.preview || timers.store.durability === "durable"),
  );
  useEffect(() => {
    let active = true;
    if (available)
      timers!.load(view.id, minutes).catch(() => {
        if (active)
          setError(
            "The saved timer could not be read. Reset saved timer explicitly to replace it.",
          );
      });
    return () => {
      active = false;
    };
  }, [available, timers, view.id, minutes]);
  if (!available)
    return (
      <Notice>
        This timer requires a durable store scoped to your account and app. It
        is unavailable in this live host.
      </Notice>
    );
  const operation = async (kind: "start" | "pause" | "resume" | "reset") => {
    setError(null);
    try {
      await timers!.change(view.id, kind, minutes);
    } catch {
      setError("The timer could not be saved. Its previous state is retained.");
    }
  };
  if (!state)
    return (
      <View style={{ gap: 8 }}>
        {error ? <Notice error>{error}</Notice> : <Body>Loading timer…</Body>}
        {error ? (
          <Button onPress={() => void operation("reset")}>
            Reset saved timer
          </Button>
        ) : null}
      </View>
    );
  const remaining = remainingAt(state, now),
    seconds = Math.ceil(remaining / 1000),
    phase = phaseAt(state, now);
  return (
    <View style={{ gap: 12 }}>
      <Body heading>
        {Math.floor(seconds / 60)}:{String(seconds % 60).padStart(2, "0")}
      </Body>
      <Body>{phase === "complete" ? "Timer complete" : phase}</Body>
      <Body muted>
        {controller.adapter.preview
          ? "Isolated preview timer; never schedules a device notification."
          : "This timer uses a saved deadline. No device notification is scheduled."}
      </Body>
      <Row>
        {phase === "ready" ? (
          <Button onPress={() => void operation("start")}>Start</Button>
        ) : null}
        {phase === "running" ? (
          <Button onPress={() => void operation("pause")}>Pause</Button>
        ) : null}
        {phase === "paused" ? (
          <Button onPress={() => void operation("resume")}>Resume</Button>
        ) : null}
        <Button subtle onPress={() => void operation("reset")}>
          Reset
        </Button>
      </Row>
      {error ? <Notice error>{error}</Notice> : null}
    </View>
  );
}
const previewDevice: DeviceState = {
  batteryLevel: 0.82,
  charging: false,
  model: "Example phone",
  osVersion: "Preview OS",
  connection: "Example connection",
  language: "en",
  region: "US",
  timeZone: "America/Los_Angeles",
};
export function DeviceInfoView({ view }: { view: ViewSpecOf<"deviceInfo"> }) {
  const { controller, device } = useRuntime(),
    preview = controller.adapter.preview,
    fields = view.options!.fields,
    [response, setResponse] = useState<{
      source: DeviceBridge;
      key: string;
      state?: DeviceState;
      error?: string;
    } | null>(null),
    key = fields.join(":"),
    available = Boolean(
      device &&
      fields.every((field) =>
        device.available.includes(deviceFieldCapability(field)),
      ),
    ),
    current =
      response?.source === device && response?.key === key ? response : null,
    state = preview ? previewDevice : current?.state,
    error =
      !preview && !available
        ? "The requested device information is unavailable on this host."
        : current?.error;
  useEffect(() => {
    let active = true;
    if (preview || !available || !device) return;
    device.read(fields).then(
      (value) => {
        if (active) setResponse({ source: device, key, state: value });
      },
      () => {
        if (active)
          setResponse({
            source: device,
            key,
            error: "Device information could not be read.",
          });
      },
    );
    return () => {
      active = false;
    };
  }, [device, fields, preview, available, key]);
  return (
    <View style={{ gap: 8 }}>
      {preview ? (
        <Notice>
          Synthetic device information. This preview never reads your device.
        </Notice>
      ) : null}
      {error ? (
        <Notice error>{error}</Notice>
      ) : state ? (
        fields.map((field) => (
          <Body key={field}>
            {field}:{" "}
            {field === "batteryLevel" && typeof state[field] === "number"
              ? `${Math.round(Number(state[field]) * 100)}%`
              : state[field] === null || state[field] === undefined
                ? "Unavailable"
                : String(state[field])}
          </Body>
        ))
      ) : (
        <Body>Loading device information…</Body>
      )}
    </View>
  );
}
export function DeviceControlView({
  view,
}: {
  view: ViewSpecOf<"deviceControl">;
}) {
  const { controller, device } = useRuntime(),
    preview = controller.adapter.preview,
    control = view.options!.control,
    [value, setValue] = useState(control === "brightness" ? "0.5" : "false"),
    [error, setError] = useState<string | null>(null),
    [busy, setBusy] = useState(false),
    available = preview || Boolean(device?.available.includes(control));
  useEffect(() => {
    return () => {
      if (!preview && device) void device.release(control).catch(() => {});
    };
  }, [preview, device, control]);
  const apply = async () => {
    setError(null);
    const next =
      control === "brightness"
        ? Number(value)
        : control === "haptics"
          ? undefined
          : value !== "true";
    if (
      control === "brightness" &&
      (!Number.isFinite(next) || Number(next) < 0 || Number(next) > 1)
    ) {
      setError("Brightness must be between zero and one.");
      return;
    }
    setBusy(true);
    try {
      if (!preview) await device!.control(control, next);
      if (typeof next === "boolean") setValue(String(next));
    } catch {
      setError("This device control could not be applied.");
    } finally {
      setBusy(false);
    }
  };
  return (
    <View style={{ gap: 12 }}>
      {preview ? (
        <Notice>
          Isolated preview. This control never changes your device.
        </Notice>
      ) : null}
      {!available ? (
        <Notice>This device control is unavailable on this host.</Notice>
      ) : null}
      {control === "brightness" ? (
        <Input
          accessibilityLabel="Brightness from zero to one"
          value={value}
          onChangeText={setValue}
          keyboardType="decimal-pad"
          editable={available && !busy}
        />
      ) : null}
      <Button disabled={!available || busy} onPress={() => void apply()}>
        {control === "haptics"
          ? "Try haptic feedback"
          : control === "brightness"
            ? "Set brightness"
            : `${value === "true" ? "Turn off" : "Turn on"} ${control}`}
      </Button>
      {error ? <Notice error>{error}</Notice> : null}
    </View>
  );
}
