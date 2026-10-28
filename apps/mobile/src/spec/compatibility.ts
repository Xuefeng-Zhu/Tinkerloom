import { canonicalJson } from "./schema";
import type { AppSpec } from "./types";

/** Definition compatibility is not a data migration, backup or effect rollback. */
export function compatibilityErrors(
  previous: AppSpec,
  next: AppSpec,
): string[] {
  const errors: string[] = [];
  if (previous.policyPresetRequest !== next.policyPresetRequest)
    errors.push("Changing the permission preset is unsupported");
  for (const old of previous.collections) {
    const collection = next.collections.find(
      (candidate) => candidate.id === old.id,
    );
    if (!collection) {
      errors.push(`Removing collection ${old.id} is unsupported`);
      continue;
    }
    for (const field of old.fields) {
      const current = collection.fields.find(
        (candidate) => candidate.id === field.id,
      );
      if (
        !current ||
        current.type !== field.type ||
        (!field.required && current.required) ||
        (field.choices ?? []).some(
          (choice) => !current.choices?.includes(choice),
        )
      )
        errors.push(`Destructive change to ${old.id}.${field.id}`);
    }
    for (const field of collection.fields)
      if (
        field.required &&
        !old.fields.some((candidate) => candidate.id === field.id)
      )
        errors.push(`Required field ${old.id}.${field.id} needs a backfill`);
    if (canonicalJson(old.behaviors) !== canonicalJson(collection.behaviors))
      errors.push(`Changing existing behaviors on ${old.id} is unsupported`);
  }
  return errors;
}
