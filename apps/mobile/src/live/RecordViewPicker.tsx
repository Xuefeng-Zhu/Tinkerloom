import { Pressable, StyleSheet, Text, View } from "react-native";
import { colors, space } from "../components/theme";
import type { Definition } from "../preview/model";

export function RecordViewPicker({
  definition,
  disabled = false,
  onChange,
}: {
  definition: Definition;
  disabled?: boolean;
  onChange: (view: NonNullable<Definition["view"]>) => void;
}) {
  const kind = definition.view?.kind ?? "list";
  const dates = definition.fields.filter((field) => field.kind === "date");
  return (
    <View style={styles.section}>
      <Text accessibilityRole="header" style={styles.title}>
        Record layout
      </Text>
      <View
        accessibilityRole="radiogroup"
        accessibilityLabel="Record layout"
        style={styles.choices}
      >
        {(["list", "table", "agenda"] as const).map((option) => {
          const unavailable =
            disabled || (option === "agenda" && !dates.length);
          return (
            <Pressable
              key={option}
              accessibilityRole="radio"
              accessibilityLabel={`${option[0].toUpperCase()}${option.slice(1)} layout`}
              accessibilityState={{
                checked: kind === option,
                disabled: unavailable,
              }}
              disabled={unavailable}
              style={[
                styles.choice,
                kind === option && styles.selected,
                unavailable && styles.disabled,
              ]}
              onPress={() =>
                onChange(
                  option === "agenda"
                    ? {
                        kind: option,
                        dateFieldId:
                          definition.view?.dateFieldId ?? dates[0].id,
                      }
                    : { kind: option },
                )
              }
            >
              <Text style={styles.choiceText}>
                {option[0].toUpperCase()}
                {option.slice(1)}
              </Text>
            </Pressable>
          );
        })}
      </View>
      {kind === "agenda" ? (
        <>
          <Text style={styles.hint}>
            Group records by this date field. Undated records have their own
            section.
          </Text>
          <View
            accessibilityRole="radiogroup"
            accessibilityLabel="Agenda date field"
            style={styles.choices}
          >
            {dates.map((field) => (
              <Pressable
                key={field.id}
                accessibilityRole="radio"
                accessibilityLabel={`Group agenda by ${field.label}`}
                accessibilityState={{
                  checked: definition.view?.dateFieldId === field.id,
                  disabled,
                }}
                disabled={disabled}
                style={[
                  styles.choice,
                  definition.view?.dateFieldId === field.id && styles.selected,
                  disabled && styles.disabled,
                ]}
                onPress={() =>
                  onChange({ kind: "agenda", dateFieldId: field.id })
                }
              >
                <Text style={styles.choiceText}>{field.label}</Text>
              </Pressable>
            ))}
          </View>
        </>
      ) : (
        <Text style={styles.hint}>
          {dates.length
            ? "Choose how this app presents its records."
            : "Add a date field to use an agenda."}
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  section: { gap: space.md },
  title: { color: colors.ink, fontSize: 18, fontWeight: "600" },
  choices: { flexDirection: "row", flexWrap: "wrap", gap: space.sm },
  choice: {
    minHeight: 44,
    justifyContent: "center",
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: 12,
  },
  choiceText: { color: colors.ink, fontSize: 14 },
  selected: { borderColor: colors.ink, backgroundColor: colors.sage },
  disabled: { opacity: 0.5 },
  hint: { color: colors.muted, fontSize: 13, lineHeight: 21 },
});
