import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { Button } from "../components/Button";
import { colors, space } from "../components/theme";
import type { Definition, Field } from "../preview/model";
import {
  agendaGroups,
  DisplayRecord,
  displayFieldValue,
} from "./recordPresentation";

interface RecordsViewProps<T extends DisplayRecord> {
  definition: Definition;
  records: readonly T[];
  onEdit: (record: T) => void;
  editDisabled?: boolean;
  onToggle?: (record: T, fieldId: string) => void;
}

export function RecordsView<T extends DisplayRecord>(
  props: RecordsViewProps<T>,
) {
  const { definition, records } = props;
  const kind = definition.view?.kind ?? "list";
  if (kind === "table") return <RecordsTable {...props} />;
  if (kind === "agenda" && definition.view?.dateFieldId) {
    return (
      <View style={styles.groups}>
        {agendaGroups(records, definition.view.dateFieldId).map((group) => (
          <View key={group.date ?? "undated"} style={styles.group}>
            <Text accessibilityRole="header" style={styles.groupTitle}>
              {group.date ?? "Undated"}
            </Text>
            {group.records.map((record) => (
              <RecordCard key={record.id} {...props} record={record} />
            ))}
          </View>
        ))}
      </View>
    );
  }
  return (
    <View style={styles.groups}>
      {records.map((record) => (
        <RecordCard key={record.id} {...props} record={record} />
      ))}
    </View>
  );
}

function RecordCell<T extends DisplayRecord>({
  field,
  record,
  onToggle,
  editDisabled,
}: {
  field: Field;
  record: T;
  onToggle?: (record: T, fieldId: string) => void;
  editDisabled?: boolean;
}) {
  if (field.kind === "boolean" && onToggle)
    return (
      <Pressable
        accessibilityRole="checkbox"
        accessibilityLabel={field.label}
        accessibilityState={{
          checked: record.values[field.id] === true,
          disabled: editDisabled,
        }}
        disabled={editDisabled}
        onPress={() => onToggle(record, field.id)}
        style={styles.checkRow}
      >
        <View
          style={[
            styles.check,
            record.values[field.id] === true && styles.checked,
          ]}
        >
          <Text style={styles.checkMark}>
            {record.values[field.id] === true ? "✓" : ""}
          </Text>
        </View>
        <Text style={styles.value}>
          {record.values[field.id] === true ? "Yes" : "No"}
        </Text>
      </Pressable>
    );
  return (
    <Text
      numberOfLines={field.kind === "longText" ? 4 : undefined}
      style={styles.value}
    >
      {displayFieldValue(field, record.values[field.id])}
    </Text>
  );
}

function RecordCard<T extends DisplayRecord>({
  definition,
  record,
  onEdit,
  editDisabled,
  onToggle,
}: RecordsViewProps<T> & { record: T }) {
  const primary = definition.fields.find(
    (field) => field.id === definition.primaryFieldId,
  )!;
  const title = displayFieldValue(primary, record.values[primary.id]);
  return (
    <View style={styles.card}>
      <View style={styles.topline}>
        <Text accessibilityRole="header" style={styles.recordTitle}>
          {title}
        </Text>
        <Button
          label="Edit"
          accessibilityLabel={`Edit ${title}`}
          variant="quiet"
          disabled={editDisabled}
          onPress={() => onEdit(record)}
        />
      </View>
      {definition.fields
        .filter((field) => field.id !== primary.id)
        .map((field) => (
          <View key={field.id} style={styles.field}>
            <Text style={styles.fieldLabel}>{field.label}</Text>
            <RecordCell
              field={field}
              record={record}
              onToggle={onToggle}
              editDisabled={editDisabled}
            />
          </View>
        ))}
    </View>
  );
}

function RecordsTable<T extends DisplayRecord>({
  definition,
  records,
  onEdit,
  editDisabled,
  onToggle,
}: RecordsViewProps<T>) {
  return (
    <View style={styles.tableFrame}>
      <Text style={styles.scrollHint}>
        Scroll horizontally to see all fields.
      </Text>
      <ScrollView
        horizontal
        accessibilityLabel="Record table"
        contentContainerStyle={styles.table}
      >
        <View>
          <View style={[styles.tableRow, styles.tableHeader]}>
            {definition.fields.map((field) => (
              <Text
                key={field.id}
                accessibilityRole="header"
                style={[styles.tableCell, styles.fieldLabel]}
              >
                {field.label}
              </Text>
            ))}
            <Text style={[styles.actionCell, styles.fieldLabel]}>Actions</Text>
          </View>
          {records.map((record) => (
            <View key={record.id} style={styles.tableRow}>
              {definition.fields.map((field) => (
                <View key={field.id} style={styles.tableCell}>
                  <RecordCell
                    field={field}
                    record={record}
                    onToggle={onToggle}
                    editDisabled={editDisabled}
                  />
                </View>
              ))}
              <View style={styles.actionCell}>
                <Button
                  label="Edit"
                  accessibilityLabel={`Edit ${String(record.values[definition.primaryFieldId])}`}
                  variant="quiet"
                  disabled={editDisabled}
                  onPress={() => onEdit(record)}
                />
              </View>
            </View>
          ))}
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  groups: { gap: space.md },
  group: { gap: space.md },
  groupTitle: {
    color: colors.ink,
    fontSize: 18,
    fontWeight: "600",
    paddingTop: space.sm,
  },
  card: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: space.lg,
    gap: space.md,
  },
  topline: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: space.md,
  },
  recordTitle: {
    color: colors.ink,
    fontSize: 20,
    fontWeight: "600",
    lineHeight: 28,
    flex: 1,
  },
  field: { gap: space.xs },
  fieldLabel: {
    color: colors.ink,
    fontSize: 13,
    fontWeight: "600",
    lineHeight: 20,
  },
  value: { color: colors.muted, fontSize: 15, lineHeight: 23 },
  tableFrame: { gap: space.sm },
  scrollHint: { color: colors.muted, fontSize: 12, lineHeight: 19 },
  table: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    overflow: "hidden",
  },
  tableRow: {
    flexDirection: "row",
    backgroundColor: colors.surface,
    borderBottomWidth: 1,
    borderColor: colors.border,
  },
  tableHeader: { backgroundColor: colors.sage },
  tableCell: {
    width: 176,
    padding: space.md,
    borderRightWidth: 1,
    borderColor: colors.border,
  },
  actionCell: { width: 104, padding: space.sm, justifyContent: "center" },
  checkRow: {
    minHeight: 44,
    flexDirection: "row",
    alignItems: "center",
    gap: space.sm,
  },
  check: {
    width: 24,
    height: 24,
    borderWidth: 1,
    borderColor: colors.muted,
    borderRadius: 6,
    alignItems: "center",
    justifyContent: "center",
  },
  checked: { backgroundColor: colors.ink, borderColor: colors.ink },
  checkMark: { color: colors.surface, fontSize: 16, fontWeight: "600" },
});
