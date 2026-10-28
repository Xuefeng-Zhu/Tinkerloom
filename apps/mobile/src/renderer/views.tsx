import { ownValue } from "../spec/ownValue";
import { useEffect, useState, useRef } from "react";
import type { ComponentRef } from "react";
import {
  Pressable,
  ScrollView,
  Text,
  View,
  useWindowDimensions,
} from "react-native";
import { fieldsForView, getCollection, getField } from "../spec/bindings";
import type { ViewSpec, ViewSpecOf } from "../spec/types";
import type { RuntimeRecord } from "../runtime/types";
import { localDayKey } from "../runtime/query";
import { useRuntime } from "./context";
import { Body, Button, Input, Notice, Panel, Row } from "./primitives";
import { FieldValue, PrivateImage, RecordReminder } from "./fields";
import { RecordForm } from "./form";
import { ViewActions } from "./actions";
import { DraggableBoardRecord } from "./board";
import { chartNumber, AggregateChart } from "./charts";
import {
  checklistChecked,
  checklistCommand,
  displayField,
  markdownBlocks,
  markdownSpans,
  recordTitle,
} from "./model";
import {
  ClockView,
  DeviceControlView,
  DeviceInfoView,
  TimerView,
} from "./utilities";

function ViewFilters({ view }: { view: ViewSpec }) {
  const { controller, state } = useRuntime(),
    settings = controller.settingsFor(view.id),
    [search, setSearch] = useState(settings.search ?? ""),
    [error, setError] = useState<string | null>(null),
    collection = view.collectionId
      ? getCollection(controller.adapter.spec, view.collectionId)
      : null,
    title = collection?.fields.find((field) => field.id === view.titleFieldId),
    enabled = Boolean(
      view.filterFieldIds?.length &&
      title?.type === "text" &&
      view.type !== "summary",
    );
  useEffect(() => {
    if (!enabled || search === (settings.search ?? "")) return;
    const timer = setTimeout(() => {
      void controller
        .select(view.id, { search })
        .catch(() =>
          setError("Finish the current edit before changing the search."),
        );
    }, 250);
    return () => clearTimeout(timer);
  }, [controller, enabled, search, settings.search, view.id]);
  const fields =
    collection?.fields.filter(
      (field) =>
        view.filterFieldIds?.includes(field.id) && field.type === "choice",
    ) ?? [];
  return (
    <View style={{ gap: 10 }}>
      {enabled ? (
        <Input
          accessibilityLabel={`Search ${view.label}`}
          placeholder={`Search ${title!.label.toLowerCase()}`}
          value={search}
          onChangeText={setSearch}
          editable={!state.dirty && !state.pending}
        />
      ) : null}
      {fields.map((field) => (
        <View key={field.id} style={{ gap: 4 }}>
          <Body muted>{field.label}</Body>
          <Row>
            <Button
              subtle
              selected={!settings.choices?.[field.id]}
              disabled={state.dirty || Boolean(state.pending)}
              onPress={() =>
                void controller
                  .select(view.id, {
                    choices: { ...settings.choices, [field.id]: "" },
                  })
                  .catch(() => {})
              }
            >
              All
            </Button>
            {field.choices!.map((choice) => (
              <Button
                key={choice}
                subtle
                selected={settings.choices?.[field.id] === choice}
                disabled={state.dirty || Boolean(state.pending)}
                onPress={() =>
                  void controller
                    .select(view.id, {
                      choices: { ...settings.choices, [field.id]: choice },
                    })
                    .catch(() => {})
                }
              >
                {choice}
              </Button>
            ))}
          </Row>
        </View>
      ))}
      {error ? <Notice error>{error}</Notice> : null}
    </View>
  );
}
export function RecordCard({
  view,
  record,
  actions = true,
}: {
  view: ViewSpec;
  record: RuntimeRecord;
  actions?: boolean;
}) {
  const { controller, openRecord, theme } = useRuntime(),
    fields = fieldsForView(controller.adapter.spec, view),
    titleFieldId =
      view.titleFieldId ??
      getCollection(controller.adapter.spec, record.collectionId).fields[0].id,
    title = recordTitle(controller.adapter.spec, view, record);
  return (
    <View
      style={{
        padding: view.presentation === "compact" ? 10 : 14,
        borderWidth: 1,
        borderColor: theme.outline,
        borderRadius: Math.min(theme.radius, 14),
        gap: 10,
      }}
    >
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`Open ${title}`}
        onPress={() => openRecord(view, record)}
        style={{ minHeight: 44, justifyContent: "center" }}
      >
        <Body heading={view.presentation !== "compact"}>{title}</Body>
      </Pressable>
      {fields
        .filter(
          (field) =>
            field.id !== titleFieldId &&
            ownValue(record.data, field.id) !== undefined &&
            (!["action", "capacity"].includes(view.type) ||
              Boolean(view.fieldIds?.length)),
        )
        .map((field) => (
          <FieldValue
            key={field.id}
            field={field}
            value={ownValue(record.data, field.id)}
          />
        ))}
      {record.capacity !== null ? (
        <Body>
          {record.allocated} of {record.capacity} signed up
          {record.claimed ? " · You are signed up" : ""}
        </Body>
      ) : null}
      <RecordReminder record={record} />
      {actions ? <ViewActions view={view} record={record} /> : null}
    </View>
  );
}
function RecordList({
  view,
  records,
}: {
  view: ViewSpec;
  records: readonly RuntimeRecord[];
}) {
  return (
    <View style={{ gap: 12 }}>
      {records.map((record) => (
        <RecordCard key={record.id} view={view} record={record} />
      ))}
    </View>
  );
}
function RecordTable({ view }: { view: ViewSpecOf<"table"> }) {
  const dimensions = useWindowDimensions();
  const { controller, state, openRecord, theme } = useRuntime(),
    data = state.views[view.id],
    fields = fieldsForView(controller.adapter.spec, view),
    sort = controller.settingsFor(view.id).sort;
  if (dimensions.width < 640 || dimensions.fontScale >= 1.5)
    return (
      <View style={{ gap: 12 }}>
        <Body muted>Sort the complete matching collection</Body>
        <Row>
          {fields
            .filter((field) => field.type !== "image")
            .map((field) => (
              <Button
                key={field.id}
                subtle
                selected={sort?.fieldId === field.id}
                disabled={state.dirty || Boolean(state.pending)}
                onPress={() =>
                  void controller
                    .select(view.id, {
                      sort: {
                        fieldId: field.id,
                        descending:
                          sort?.fieldId === field.id ? !sort.descending : false,
                      },
                    })
                    .catch(() => {})
                }
              >
                {field.label}
                {sort?.fieldId === field.id
                  ? sort.descending
                    ? " ↓"
                    : " ↑"
                  : ""}
              </Button>
            ))}
        </Row>
        <RecordList view={view} records={data?.records ?? []} />
        <Body muted>
          {data?.records.length ?? 0} of {data?.total ?? 0} loaded.
        </Body>
      </View>
    );
  return (
    <ScrollView horizontal contentContainerStyle={{ flexGrow: 1 }}>
      <View style={{ minWidth: Math.max(400, fields.length * 160) }}>
        <View style={{ flexDirection: "row", backgroundColor: theme.canvas }}>
          {fields.map((field) => (
            <Pressable
              key={field.id}
              accessibilityRole="button"
              accessibilityLabel={`Sort by ${field.label}${sort?.fieldId === field.id && sort.descending ? ", currently descending" : ""}`}
              disabled={
                field.type === "image" || state.dirty || Boolean(state.pending)
              }
              onPress={() =>
                void controller
                  .select(view.id, {
                    sort: {
                      fieldId: field.id,
                      descending:
                        sort?.fieldId === field.id ? !sort.descending : false,
                    },
                  })
                  .catch(() => {})
              }
              style={{ width: 160, padding: 12, minHeight: 48 }}
            >
              <Body>
                {field.label}
                {sort?.fieldId === field.id
                  ? sort.descending
                    ? " ↓"
                    : " ↑"
                  : ""}
              </Body>
            </Pressable>
          ))}
        </View>
        {data?.records.map((record) => (
          <Pressable
            key={record.id}
            accessibilityRole="button"
            accessibilityLabel={`Open ${recordTitle(controller.adapter.spec, view, record)}`}
            onPress={() => openRecord(view, record)}
            style={{
              flexDirection: "row",
              borderBottomWidth: 1,
              borderColor: theme.outline,
              minHeight: 48,
            }}
          >
            {fields.map((field) => (
              <View key={field.id} style={{ width: 160, padding: 12 }}>
                {field.type === "image" &&
                typeof ownValue(record.data, field.id) === "string" ? (
                  <PrivateImage
                    assetId={String(ownValue(record.data, field.id))}
                    alt={field.label}
                  />
                ) : (
                  <Body>
                    {displayField(field, ownValue(record.data, field.id))}
                  </Body>
                )}
              </View>
            ))}
          </Pressable>
        ))}
        <Body muted>
          Sort applies to the complete matching collection.{" "}
          {data?.records.length ?? 0} of {data?.total ?? 0} loaded.
        </Body>
      </View>
    </ScrollView>
  );
}
function BoardView({ view }: { view: ViewSpecOf<"board"> }) {
  const columns = useRef(new Map<string, ComponentRef<typeof View>>());
  const { controller, state } = useRuntime(),
    data = state.views[view.id],
    collection = getCollection(controller.adapter.spec, view.collectionId),
    field = getField(collection, view.groupByFieldId!),
    groups = [
      ...(field.choices ?? []),
      ...(data?.records.some(
        (record) => ownValue(record.data, field.id) === undefined,
      )
        ? [""]
        : []),
    ];
  const dropTarget = async (x: number, y: number) => {
    const bounds = await Promise.all(
      [...columns.current].map(
        ([key, node]) =>
          new Promise<{
            key: string;
            x: number;
            y: number;
            width: number;
            height: number;
          }>((resolve) =>
            node.measureInWindow((left, top, width, height) =>
              resolve({ key, x: left, y: top, width, height }),
            ),
          ),
      ),
    );
    return (
      bounds.find(
        (bound) =>
          x >= bound.x &&
          x < bound.x + bound.width &&
          y >= bound.y &&
          y < bound.y + bound.height,
      )?.key ?? null
    );
  };
  return (
    <View style={{ gap: 12 }}>
      <Body muted>
        {data?.records.length ?? 0} of {data?.total ?? 0} matching records
        loaded. Column totals use the complete query.
      </Body>
      <ScrollView horizontal>
        <View
          style={{ flexDirection: "row", alignItems: "flex-start", gap: 16 }}
        >
          {groups.map((group) => (
            <View
              key={group}
              collapsable={false}
              ref={(node) => {
                if (node) columns.current.set(group, node);
                else columns.current.delete(group);
              }}
              style={{ width: 280, gap: 10, minHeight: 300 }}
            >
              <Body heading>
                {group || "Not set"}
                {group && data?.summary
                  ? ` · ${data.summary.groups[group] ?? 0}`
                  : ""}
              </Body>
              {(
                data?.records.filter(
                  (record) => (ownValue(record.data, field.id) ?? "") === group,
                ) ?? []
              ).map((record) => (
                <DraggableBoardRecord
                  key={record.id}
                  view={view}
                  record={record}
                  dropTarget={dropTarget}
                >
                  <RecordCard view={view} record={record} />
                </DraggableBoardRecord>
              ))}
            </View>
          ))}
        </View>
      </ScrollView>
      {view.options?.draggable ? (
        <Body muted>
          Use the transition buttons on a record to move it to an allowed
          column.
        </Body>
      ) : null}
    </View>
  );
}
function CalendarView({ view }: { view: ViewSpecOf<"calendar"> }) {
  const { controller, state, theme } = useRuntime(),
    settings = controller.settingsFor(view.id),
    selected = settings.selectedDay ?? new Date(),
    month = settings.month ?? selected,
    first = new Date(month.getFullYear(), month.getMonth(), 1),
    days = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate(),
    offset = (first.getDay() + 6) % 7,
    data = state.views[view.id],
    counts = new Map(
      data?.aggregate?.groups.map((group) => [group.key, group.count]) ?? [],
    ),
    busy = state.dirty || Boolean(state.pending);
  const move = (direction: number) => {
    const date = new Date(month.getFullYear(), month.getMonth() + direction, 1);
    void controller
      .select(view.id, { month: date, selectedDay: date })
      .catch(() => {});
  };
  return (
    <View style={{ gap: 12 }}>
      <Row>
        <Button
          subtle
          label="Previous month"
          disabled={busy}
          onPress={() => move(-1)}
        >
          ←
        </Button>
        <Body heading>
          {month.toLocaleDateString(undefined, {
            month: "long",
            year: "numeric",
          })}
        </Body>
        <Button
          subtle
          label="Next month"
          disabled={busy}
          onPress={() => move(1)}
        >
          →
        </Button>
      </Row>
      <View style={{ flexDirection: "row", flexWrap: "wrap" }}>
        {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((day) => (
          <View key={day} style={{ width: "14.285%", padding: 3 }}>
            <Body muted>{day}</Body>
          </View>
        ))}
        {Array.from({ length: offset + days }, (_, i) => {
          if (i < offset)
            return <View key={`empty_${i}`} style={{ width: "14.285%" }} />;
          const date = new Date(
              month.getFullYear(),
              month.getMonth(),
              i - offset + 1,
            ),
            key = localDayKey(date),
            count = counts.get(key) ?? 0,
            chosen = key === localDayKey(selected);
          return (
            <Pressable
              key={key}
              accessibilityRole="button"
              accessibilityState={{ selected: chosen, disabled: busy }}
              accessibilityLabel={`${date.toLocaleDateString()}, ${count} matching records`}
              disabled={busy}
              onPress={() =>
                void controller
                  .select(view.id, { selectedDay: date })
                  .catch(() => {})
              }
              style={{
                width: "14.285%",
                minHeight: 62,
                padding: 6,
                borderWidth: 1,
                borderColor: theme.outline,
                backgroundColor: chosen ? theme.accent : theme.surface,
              }}
            >
              <Text
                style={{
                  fontSize: 16,
                  color: chosen ? theme.onAccent : theme.ink,
                }}
              >
                {date.getDate()}
              </Text>
              <Text
                style={{
                  fontSize: 12,
                  color: chosen ? theme.onAccent : theme.muted,
                }}
              >
                {count ? `${count} records` : ""}
              </Text>
            </Pressable>
          );
        })}
      </View>
      <Body muted>
        Month badges count all matching records in each local calendar day.
      </Body>
      <Body heading>
        {selected.toLocaleDateString(undefined, {
          weekday: "long",
          month: "long",
          day: "numeric",
        })}
      </Body>
      <RecordList view={view} records={data?.records ?? []} />
    </View>
  );
}
function TimelineView({ view }: { view: ViewSpecOf<"timeline"> }) {
  const { controller, state } = useRuntime(),
    data = state.views[view.id],
    groups = new Map<string, RuntimeRecord[]>(),
    undated = controller.settingsFor(view.id).undated;
  for (const record of data?.records ?? []) {
    const raw = ownValue(record.data, view.options!.dateFieldId),
      key =
        raw === undefined
          ? "Undated"
          : new Date(String(raw)).toLocaleDateString(undefined, {
              year: "numeric",
              month: "long",
              day: "numeric",
            });
    groups.set(key, [...(groups.get(key) ?? []), record]);
  }
  return (
    <View style={{ gap: 14 }}>
      <Row>
        <Button
          subtle
          selected={!undated}
          disabled={state.dirty || Boolean(state.pending)}
          onPress={() =>
            void controller.select(view.id, { undated: false }).catch(() => {})
          }
        >
          All dates
        </Button>
        <Button
          subtle
          selected={Boolean(undated)}
          disabled={state.dirty || Boolean(state.pending)}
          onPress={() =>
            void controller.select(view.id, { undated: true }).catch(() => {})
          }
        >
          Undated only
        </Button>
      </Row>
      <Body muted>
        Groups show the {data?.records.length ?? 0} loaded records in timestamp
        order, with unset dates last. Load more to continue.
      </Body>
      {[...groups].map(([label, records]) => (
        <View key={label} style={{ gap: 10 }}>
          <Body heading>{label}</Body>
          <RecordList view={view} records={records} />
        </View>
      ))}
    </View>
  );
}
function ChecklistView({ view }: { view: ViewSpecOf<"checklist"> }) {
  const { controller, state, theme, openRecord } = useRuntime(),
    data = state.views[view.id],
    action = controller.adapter.spec.actions.find(
      (a) => a.id === view.options!.actionId,
    )!,
    [error, setError] = useState<string | null>(null);
  const toggle = async (record: RuntimeRecord) => {
    setError(null);
    try {
      await controller.execute(
        action.id,
        checklistCommand(controller.adapter.spec, view, record),
        record,
      );
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "This item could not be changed.",
      );
    }
  };
  return (
    <View style={{ gap: 10 }}>
      {data?.records.map((record) => (
        <View
          key={record.id}
          style={{ flexDirection: "row", alignItems: "center", gap: 10 }}
        >
          <Pressable
            accessibilityRole="checkbox"
            accessibilityState={{
              checked: checklistChecked(view, record),
              disabled:
                Boolean(state.pending) ||
                !controller.writeAvailable ||
                !controller.adapter.permits(action, record),
            }}
            accessibilityLabel={recordTitle(
              controller.adapter.spec,
              view,
              record,
            )}
            disabled={
              Boolean(state.pending) ||
              !controller.writeAvailable ||
              !controller.adapter.permits(action, record)
            }
            onPress={() => void toggle(record)}
            style={{
              minWidth: 48,
              minHeight: 48,
              alignItems: "center",
              justifyContent: "center",
              borderWidth: 1,
              borderColor: theme.outline,
              borderRadius: 6,
            }}
          >
            <Text style={{ fontSize: 23, color: theme.ink }}>
              {checklistChecked(view, record) ? "✓" : "○"}
            </Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            onPress={() => openRecord(view, record)}
            style={{ flex: 1, minHeight: 48, justifyContent: "center" }}
          >
            <Body>{recordTitle(controller.adapter.spec, view, record)}</Body>
          </Pressable>
        </View>
      ))}
      {error ? <Notice error>{error}</Notice> : null}
    </View>
  );
}
function ImageCollectionView({
  view,
}: {
  view: ViewSpecOf<"imageCards"> | ViewSpecOf<"gallery">;
}) {
  const { controller, state, openRecord } = useRuntime(),
    data = state.views[view.id],
    options = view.options!;
  return (
    <View
      style={{
        flexDirection: view.type === "gallery" ? "row" : "column",
        flexWrap: "wrap",
        gap: 14,
      }}
    >
      {data?.records.map((record) => (
        <View
          key={record.id}
          style={{ width: view.type === "gallery" ? 220 : "100%", gap: 8 }}
        >
          {typeof ownValue(record.data, options.imageFieldId) === "string" ? (
            <PrivateImage
              assetId={String(ownValue(record.data, options.imageFieldId))}
              alt={
                options.captionFieldId
                  ? String(
                      ownValue(record.data, options.captionFieldId) ??
                        "Private image",
                    )
                  : "Private image"
              }
            />
          ) : (
            <Notice>No image</Notice>
          )}
          <Button subtle onPress={() => openRecord(view, record)}>
            {options.captionFieldId
              ? String(
                  ownValue(record.data, options.captionFieldId) ??
                    recordTitle(controller.adapter.spec, view, record),
                )
              : recordTitle(controller.adapter.spec, view, record)}
          </Button>
          <ViewActions view={view} record={record} />
        </View>
      ))}
    </View>
  );
}
function MetricView({ view }: { view: ViewSpecOf<"metric"> }) {
  const { state, theme } = useRuntime(),
    aggregate = state.views[view.id]?.aggregate,
    target = view.options?.target,
    value = aggregate?.value ?? null;
  return (
    <View style={{ gap: 10 }}>
      <Body heading>{chartNumber(value)}</Body>
      {target !== undefined ? (
        <View style={{ gap: 6 }}>
          <Body muted>Target: {chartNumber(target)}</Body>
          <View
            accessibilityRole="progressbar"
            accessibilityValue={{
              min: 0,
              max: target,
              ...(typeof value === "number"
                ? { now: Math.max(0, Math.min(target, value)) }
                : {}),
              text: `${chartNumber(value)} of ${target}`,
            }}
            style={{
              height: 12,
              backgroundColor: theme.outline,
              borderRadius: 6,
            }}
          >
            <View
              style={{
                height: 12,
                width: `${Math.max(0, Math.min(100, ((value ?? 0) / target) * 100))}%`,
                backgroundColor: theme.accent,
                borderRadius: 6,
              }}
            />
          </View>
        </View>
      ) : null}
      <Body muted>
        Computed from all {aggregate?.total ?? 0} matching records.
      </Body>
    </View>
  );
}
function SummaryView({ view }: { view: ViewSpecOf<"summary"> }) {
  const { state } = useRuntime(),
    summary = state.views[view.id]?.summary;
  return (
    <View style={{ gap: 8 }}>
      <Body heading>{summary?.total ?? 0} total</Body>
      {Object.entries(summary?.groups ?? {}).map(([key, count]) => (
        <Body key={key}>
          {key}: {count}
        </Body>
      ))}
      <Body muted>
        Counts use all matching records. Unset values contribute to the total.
      </Body>
    </View>
  );
}
export function DetailsView({
  view,
  record,
}: {
  view: ViewSpec;
  record?: RuntimeRecord | null;
}) {
  const { controller } = useRuntime();
  if (!record || record.collectionId !== view.collectionId)
    return <Notice>Select a record to view its details.</Notice>;
  return (
    <View style={{ gap: 14 }}>
      <Body heading>{recordTitle(controller.adapter.spec, view, record)}</Body>
      {fieldsForView(controller.adapter.spec, view).map((field) => (
        <FieldValue
          key={field.id}
          field={field}
          value={ownValue(record.data, field.id)}
        />
      ))}
      {record.capacity !== null ? (
        <Body>
          {record.allocated} of {record.capacity} signed up.
        </Body>
      ) : null}
      <RecordReminder record={record} />
      <ViewActions view={view} record={record} />
    </View>
  );
}
function ContentView({ view }: { view: ViewSpec }) {
  const { theme } = useRuntime();
  switch (view.type) {
    case "richText":
      return (
        <View style={{ gap: 10 }}>
          {markdownBlocks(view.options!.markdown).map((block, index) => (
            <Text
              key={index}
              accessibilityRole={
                block.kind === "heading" ? "header" : undefined
              }
              style={{
                color: theme.ink,
                lineHeight: block.kind === "heading" ? 30 : 24,
                fontSize:
                  block.kind === "heading" ? 26 - (block.level ?? 1) * 2 : 16,
                fontWeight: block.kind === "heading" ? "600" : "400",
                ...(block.kind === "quote"
                  ? {
                      borderLeftWidth: 3,
                      borderLeftColor: theme.outline,
                      paddingLeft: 12,
                      fontStyle: "italic",
                    }
                  : {}),
              }}
            >
              {block.kind === "bullet" ? "• " : ""}
              {markdownSpans(block.text).map((span, i) => (
                <Text
                  key={i}
                  style={
                    span.style === "strong"
                      ? { fontWeight: "700" }
                      : span.style === "emphasis"
                        ? { fontStyle: "italic" }
                        : span.style === "code"
                          ? { fontFamily: "monospace" }
                          : undefined
                  }
                >
                  {span.text}
                </Text>
              ))}
            </Text>
          ))}
        </View>
      );
    case "banner":
      return <BannerView view={view} />;
    case "clock":
      return <ClockView view={view} />;
    case "timer":
      return <TimerView view={view} />;
    case "deviceInfo":
      return <DeviceInfoView view={view} />;
    case "deviceControl":
      return <DeviceControlView view={view} />;
    default:
      return null;
  }
}
function BannerView({ view }: { view: ViewSpecOf<"banner"> }) {
  const { controller, theme, navigate } = useRuntime(),
    options = view.options!,
    dimensions = useWindowDimensions(),
    [width, setWidth] = useState(0),
    [expanded, setExpanded] = useState(false),
    beside =
      options.imagePlacement === "beside" &&
      width >= 640 &&
      dimensions.fontScale < 1.5,
    compact =
      width > 0 &&
      width < 640 &&
      !options.imageAssetId &&
      options.body &&
      !options.targetPageId &&
      options.tone !== "warning",
    background =
      options.tone === "success"
        ? "#edf7ef"
        : options.tone === "warning"
          ? "#fff5dc"
          : options.tone === "info"
            ? "#edf5ff"
            : theme.canvas;
  const target = controller.adapter.spec.navigation?.pages.find(
    (page) => page.id === options.targetPageId,
  );
  return (
    <View
      onLayout={(event) => setWidth(event.nativeEvent.layout.width)}
      style={{
        backgroundColor: background,
        borderRadius: theme.radius,
        overflow: "hidden",
        gap: 14,
        flexDirection: beside ? "row" : "column",
      }}
    >
      {options.imageAssetId ? (
        <View style={{ flex: beside ? 1 : undefined }}>
          <PrivateImage assetId={options.imageAssetId} alt={options.imageAlt} />
        </View>
      ) : null}
      <View style={{ flex: beside ? 1 : undefined, padding: 16, gap: 12 }}>
        {compact ? (
          <Pressable
            accessibilityRole="button"
            accessibilityState={{ expanded }}
            onPress={() => setExpanded((value) => !value)}
            style={{ minHeight: 44, justifyContent: "center" }}
          >
            <Body heading>
              {options.title} {expanded ? "−" : "+"}
            </Body>
          </Pressable>
        ) : (
          <Body heading>{options.title}</Body>
        )}
        {options.body && (!compact || expanded) ? (
          <Body>{options.body}</Body>
        ) : null}
        {options.targetPageId ? (
          <Button onPress={() => navigate({ pageId: options.targetPageId! })}>
            Open {target?.title ?? "page"}
          </Button>
        ) : null}
      </View>
    </View>
  );
}
export function SemanticView({ view }: { view: ViewSpec }) {
  const { controller, state } = useRuntime(),
    data = state.views[view.id],
    content = !view.collectionId;
  let body;
  switch (view.type) {
    case "richText":
    case "banner":
    case "clock":
    case "timer":
    case "deviceInfo":
    case "deviceControl":
      body = <ContentView view={view} />;
      break;
    case "form":
      body =
        state.location.recordId &&
        (!state.record || state.record.collectionId !== view.collectionId) ? (
          <Notice>
            {state.loading
              ? "Loading the record to edit…"
              : "The record is unavailable. Open it again before editing."}
          </Notice>
        ) : (
          <RecordForm
            key={`${view.id}:${state.record?.id ?? "new"}:${state.record?.revision ?? 0}`}
            view={view}
            record={
              state.location.recordId ? (state.record ?? undefined) : undefined
            }
          />
        );
      break;
    case "details":
      body = <DetailsView view={view} record={state.record} />;
      break;
    case "table":
      body = <RecordTable view={view} />;
      break;
    case "calendar":
      body = <CalendarView view={view} />;
      break;
    case "timeline":
      body = <TimelineView view={view} />;
      break;
    case "board":
      body = <BoardView view={view} />;
      break;
    case "summary":
      body = <SummaryView view={view} />;
      break;
    case "metric":
      body = <MetricView view={view} />;
      break;
    case "chart":
      body = data?.aggregate ? (
        <AggregateChart
          aggregate={data.aggregate}
          style={view.options!.style}
        />
      ) : null;
      break;
    case "gallery":
    case "imageCards":
      body = <ImageCollectionView view={view} />;
      break;
    case "checklist":
      body = <ChecklistView view={view} />;
      break;
    case "action":
    case "capacity":
    case "list":
      body = <RecordList view={view} records={data?.records ?? []} />;
      break;
    default: {
      const unsupported: never = view;
      throw new Error(`Unsupported semantic view: ${String(unsupported)}`);
    }
  }
  return (
    <Panel title={view.label}>
      {!content && !["form", "details"].includes(view.type) ? (
        <>
          <ViewActions view={view} createOnly />
          <ViewFilters view={view} />
        </>
      ) : null}
      {data?.error ? <Notice error>{data.error.message}</Notice> : body}
      {!content &&
      !data?.loading &&
      !data?.error &&
      !["form", "details", "summary", "metric", "chart"].includes(view.type) &&
      !data?.records.length ? (
        <Body muted>No matching records.</Body>
      ) : null}
      {data?.loading ? <Body muted>Loading…</Body> : null}
      {data?.nextCursor ? (
        <Button
          subtle
          disabled={data.loading || state.dirty || Boolean(state.pending)}
          onPress={() => void controller.loadMore(view.id)}
        >
          Load more ({data.records.length} of {data.total})
        </Button>
      ) : null}
    </Panel>
  );
}
