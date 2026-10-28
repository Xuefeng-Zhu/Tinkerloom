import { Text, View } from "react-native";
import type { RuntimeAggregate } from "../runtime/types";
import { useRuntime } from "./context";
import { Body, Notice } from "./primitives";
const colors = [
  "#177d79",
  "#a86012",
  "#386ad2",
  "#af4b71",
  "#507963",
  "#7256a6",
];
export const chartNumber = (number: number | null) =>
  number === null
    ? "No value"
    : new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(
        number,
      );
export function AggregateChart({
  aggregate,
  style,
}: {
  aggregate: RuntimeAggregate;
  style: "bar" | "line" | "donut";
}) {
  const { theme } = useRuntime(),
    groups = aggregate.groups,
    values = groups.map((group) => group.value ?? 0),
    min = Math.min(0, ...values),
    max = Math.max(0, ...values),
    span = max - min || 1;
  if (!groups.length)
    return (
      <Notice>
        No groups match this chart. The total uses the complete query.
      </Notice>
    );
  const legend = (
    <View style={{ gap: 8 }}>
      {groups.map((group, i) => (
        <View
          key={group.key}
          style={{ flexDirection: "row", alignItems: "center", gap: 8 }}
        >
          <View
            style={{
              width: 12,
              height: 12,
              borderRadius: 6,
              backgroundColor: colors[i % colors.length],
            }}
          />
          <Text style={{ color: theme.ink, fontSize: 15, flex: 1 }}>
            {group.key || "Not set"}: {chartNumber(group.value)} ({group.count}{" "}
            records)
          </Text>
        </View>
      ))}
    </View>
  );
  if (style === "donut") {
    const total = values.reduce((sum, value) => sum + Math.max(0, value), 0),
      positive = values.every((value) => value >= 0);
    if (!positive)
      return (
        <View style={{ gap: 12 }}>
          <Notice>
            A donut cannot represent negative values. Exact values are shown
            below.
          </Notice>
          {legend}
        </View>
      );
    const boundaries = values.reduce<number[]>(
      (result, value) => [...result, (result.at(-1) ?? 0) + value],
      [],
    );
    return (
      <View style={{ gap: 16 }}>
        <View
          accessible
          accessibilityLabel={`Donut chart, total ${chartNumber(total)}`}
          style={{ height: 170, width: 170, alignSelf: "center" }}
        >
          {Array.from({ length: 180 }, (_, index) => {
            const angle = (index * 2 * Math.PI) / 180,
              position = ((index + 0.5) / 180) * total,
              group = boundaries.findIndex((boundary) => boundary > position);
            return (
              <View
                key={index}
                style={{
                  position: "absolute",
                  left: 83 + 64 * Math.sin(angle),
                  top: 83 - 64 * Math.cos(angle),
                  width: 6,
                  height: 6,
                  borderRadius: 3,
                  backgroundColor: total
                    ? colors[Math.max(0, group) % colors.length]
                    : theme.outline,
                }}
              />
            );
          })}
          <View
            style={{
              position: "absolute",
              top: 62,
              left: 25,
              width: 120,
              alignItems: "center",
            }}
          >
            <Body heading>{chartNumber(total)}</Body>
          </View>
        </View>
        {legend}
        <Body muted>Based on all {aggregate.total} matching records.</Body>
      </View>
    );
  }
  if (style === "line") {
    const width = 280,
      height = 150,
      points = values.map((value, i) => ({
        x: groups.length === 1 ? width / 2 : (i / (groups.length - 1)) * width,
        y: height - ((value - min) / span) * height,
      }));
    return (
      <View style={{ gap: 16 }}>
        <View
          style={{
            width: 300,
            height: 180,
            alignSelf: "center",
            overflow: "hidden",
          }}
        >
          <View
            style={{
              position: "absolute",
              left: 10,
              top: 10,
              width,
              height,
              borderLeftWidth: 1,
              borderBottomWidth: 1,
              borderColor: theme.outline,
            }}
          >
            {points.map((point, index) => {
              const next = points[index + 1],
                dx = next ? next.x - point.x : 0,
                dy = next ? next.y - point.y : 0,
                length = Math.sqrt(dx * dx + dy * dy);
              return (
                <View key={groups[index].key}>
                  {next ? (
                    <View
                      style={{
                        position: "absolute",
                        left: point.x + dx / 2 - length / 2,
                        top: point.y + dy / 2 - 1,
                        width: length,
                        height: 2,
                        backgroundColor: theme.accent,
                        transform: [
                          {
                            rotate: `${(Math.atan2(dy, dx) * 180) / Math.PI}deg`,
                          },
                        ],
                      }}
                    />
                  ) : null}
                  <View
                    style={{
                      position: "absolute",
                      left: point.x - 3,
                      top: point.y - 3,
                      width: 6,
                      height: 6,
                      borderRadius: 3,
                      backgroundColor: theme.accent,
                    }}
                  />
                </View>
              );
            })}
          </View>
        </View>
        {legend}
        <Body muted>
          Based on all {aggregate.total} matching records. Values range from{" "}
          {chartNumber(min)} to {chartNumber(max)}.
        </Body>
      </View>
    );
  }
  return (
    <View style={{ gap: 12 }}>
      {groups.map((group, index) => {
        const value = group.value ?? 0;
        return (
          <View key={group.key} style={{ gap: 5 }}>
            <Body>
              {group.key || "Not set"}: {chartNumber(group.value)}
            </Body>
            <View
              accessibilityLabel={`${group.key || "Not set"}: ${chartNumber(group.value)}`}
              style={{
                height: 20,
                backgroundColor: theme.canvas,
                position: "relative",
              }}
            >
              <View
                style={{
                  position: "absolute",
                  left: `${((Math.min(0, value) - min) / span) * 100}%`,
                  width: `${(Math.abs(value) / span) * 100}%`,
                  height: 20,
                  backgroundColor: colors[index % colors.length],
                }}
              />
              <View
                style={{
                  position: "absolute",
                  left: `${(-min / span) * 100}%`,
                  width: 1,
                  height: 20,
                  backgroundColor: theme.muted,
                }}
              />
            </View>
          </View>
        );
      })}
      <Body muted>Based on all {aggregate.total} matching records.</Body>
    </View>
  );
}
