import { canonicalText } from "./canonicalText";

export type Field = {
  id: string;
  label: string;
  kind: "text" | "longText" | "boolean" | "choice" | "number" | "date";
  required?: boolean;
  options?: string[];
};

export type DefinitionView =
  | { kind: "list" | "table"; dateFieldId?: never }
  | { kind: "agenda"; dateFieldId: string };

export type Definition = {
  title: string;
  description: string;
  primaryFieldId: string;
  fields: Field[];
  view?: DefinitionView;
};

export type Values = Record<string, string | boolean | number>;
export type PreviewRecord = { id: string; values: Values };
export type PreviewTemplate = {
  id: string;
  definition: Definition;
  samples: Values[];
  caption: string;
};

export type PreviewSession = {
  source: PreviewTemplate;
  definition: Definition;
  records: PreviewRecord[];
  nextId: number;
};

export class PreviewValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PreviewValidationError";
  }
}

const copyDefinition = (definition: Definition): Definition => ({
  ...definition,
  ...(definition.view ? { view: { ...definition.view } } : {}),
  fields: definition.fields.map((field) => ({
    ...field,
    ...(field.options ? { options: [...field.options] } : {}),
  })),
});

export const NUMBER_LIMIT = 1e15;

/** A civil date is validated arithmetically, without timezone or Date rollover. */
export function isCivilDate(value: unknown): value is string {
  if (
    typeof value !== "string" ||
    value.length !== 10 ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value)
  )
    return false;
  const year = Number(value.slice(0, 4));
  const month = Number(value.slice(5, 7));
  const day = Number(value.slice(8, 10));
  if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1)
    return false;
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= days[month - 1];
}

/** Form-only conversion. The record validator itself never coerces strings. */
export function parseNumericInput(input: string): number | "" {
  const text = input.trim();
  if (text === "") return "";
  if (!/^-?(?:\d+(?:\.\d+)?|\.\d+)$/.test(text)) {
    throw new PreviewValidationError(
      "Enter a decimal number without exponents or separators.",
    );
  }
  const value = Number(text);
  if (!Number.isFinite(value) || Math.abs(value) > NUMBER_LIMIT) {
    throw new PreviewValidationError(
      `Use a number between -${NUMBER_LIMIT} and ${NUMBER_LIMIT}.`,
    );
  }
  return Object.is(value, -0) ? 0 : value;
}

function boundedText(value: unknown, name: string, maximum: number): string {
  if (typeof value !== "string" || canonicalText(value).length === 0) {
    throw new PreviewValidationError(`${name} is required.`);
  }
  const text = canonicalText(value);
  if (text.length > maximum) {
    throw new PreviewValidationError(
      `${name} must be ${maximum} characters or fewer.`,
    );
  }
  return text;
}

export function validateDefinition(definition: Definition): void {
  boundedText(definition.title, "App title", 80);
  if (
    typeof definition.description !== "string" ||
    definition.description.length > 240
  ) {
    throw new PreviewValidationError(
      "Description must be 240 characters or fewer.",
    );
  }
  if (
    !Array.isArray(definition.fields) ||
    definition.fields.length < 1 ||
    definition.fields.length > 10
  ) {
    throw new PreviewValidationError(
      "A preview must have between 1 and 10 fields.",
    );
  }
  const ids = new Set<string>();
  for (const field of definition.fields) {
    if (!/^[a-z][a-zA-Z0-9_]{0,31}$/.test(field.id) || ids.has(field.id)) {
      throw new PreviewValidationError(
        "Fields must have unique stable identifiers.",
      );
    }
    ids.add(field.id);
    boundedText(field.label, "Field label", 64);
    if (
      !["text", "longText", "boolean", "choice", "number", "date"].includes(
        field.kind,
      )
    ) {
      throw new PreviewValidationError(
        "This preview cannot render that field type.",
      );
    }
    if (field.kind === "choice") {
      if (
        !field.options ||
        field.options.length < 1 ||
        field.options.length > 12
      ) {
        throw new PreviewValidationError(
          "Choice fields need between 1 and 12 options.",
        );
      }
      const choices = field.options.map((option) =>
        boundedText(option, "Choice", 64),
      );
      if (new Set(choices).size !== choices.length) {
        throw new PreviewValidationError("Choice options must be unique.");
      }
    } else if (field.options !== undefined) {
      throw new PreviewValidationError("Only choice fields may have options.");
    }
  }
  const primary = definition.fields.find(
    (field) => field.id === definition.primaryFieldId,
  );
  if (!primary || primary.kind !== "text" || !primary.required) {
    throw new PreviewValidationError(
      "The primary field must be required text.",
    );
  }
  if (definition.view !== undefined) {
    const view = definition.view;
    if (
      view === null ||
      typeof view !== "object" ||
      Array.isArray(view) ||
      Object.keys(view).some(
        (key) => key !== "kind" && key !== "dateFieldId",
      ) ||
      !["list", "table", "agenda"].includes(view.kind)
    ) {
      throw new PreviewValidationError("Choose a supported app view.");
    }
    if (view.kind === "agenda") {
      if (
        typeof view.dateFieldId !== "string" ||
        !definition.fields.some(
          (field) => field.id === view.dateFieldId && field.kind === "date",
        )
      ) {
        throw new PreviewValidationError(
          "An agenda needs an existing date field.",
        );
      }
    } else if (Object.prototype.hasOwnProperty.call(view, "dateFieldId")) {
      throw new PreviewValidationError(
        "Only an agenda may select a date field.",
      );
    }
  }
}

export function validateValues(definition: Definition, values: Values): Values {
  validateDefinition(definition);
  if (values === null || typeof values !== "object" || Array.isArray(values)) {
    throw new PreviewValidationError("Record values must be an object.");
  }
  const fields = new Map(definition.fields.map((field) => [field.id, field]));
  if (Object.keys(values).some((key) => !fields.has(key))) {
    throw new PreviewValidationError("This record contains an unknown field.");
  }
  const result: Values = {};
  for (const field of definition.fields) {
    const value = values[field.id];
    if (field.kind === "boolean") {
      if (value !== undefined && typeof value !== "boolean") {
        throw new PreviewValidationError(`${field.label} must be on or off.`);
      }
      result[field.id] = value ?? false;
      continue;
    }
    if (value === undefined || value === "") {
      if (field.required)
        throw new PreviewValidationError(`${field.label} is required.`);
      result[field.id] = "";
      continue;
    }
    if (field.kind === "number") {
      if (
        typeof value !== "number" ||
        !Number.isFinite(value) ||
        Math.abs(value) > NUMBER_LIMIT
      ) {
        throw new PreviewValidationError(
          `${field.label} must be a finite number between -${NUMBER_LIMIT} and ${NUMBER_LIMIT}.`,
        );
      }
      result[field.id] = Object.is(value, -0) ? 0 : value;
      continue;
    }
    if (field.kind === "date") {
      if (!isCivilDate(value))
        throw new PreviewValidationError(
          `${field.label} must be a valid date in YYYY-MM-DD format.`,
        );
      result[field.id] = value;
      continue;
    }
    if (typeof value !== "string") {
      throw new PreviewValidationError(`${field.label} must be text.`);
    }
    const text = canonicalText(value);
    if (field.required && text.length === 0) {
      throw new PreviewValidationError(`${field.label} is required.`);
    }
    const maximum = field.kind === "longText" ? 4000 : 200;
    if (text.length > maximum) {
      throw new PreviewValidationError(
        `${field.label} must be ${maximum} characters or fewer.`,
      );
    }
    if (
      field.kind === "choice" &&
      text &&
      !field.options?.some((option) => canonicalText(option) === text)
    ) {
      throw new PreviewValidationError(
        `Choose one of the available ${field.label.toLowerCase()} options.`,
      );
    }
    result[field.id] = text;
  }
  return result;
}

export function createPreviewSession(
  template: PreviewTemplate,
): PreviewSession {
  validateDefinition(template.definition);
  if (template.samples.length > 100) {
    throw new PreviewValidationError(
      "A local preview supports up to 100 records.",
    );
  }
  const source: PreviewTemplate = {
    ...template,
    definition: copyDefinition(template.definition),
    samples: template.samples.map((values) =>
      validateValues(template.definition, values),
    ),
  };
  return {
    source,
    definition: copyDefinition(source.definition),
    records: source.samples.map((values, index) => ({
      id: `sample-${index + 1}`,
      values: { ...values },
    })),
    nextId: 1,
  };
}

export function addPreviewRecord(
  session: PreviewSession,
  values: Values,
): PreviewSession {
  if (session.records.length >= 100) {
    throw new PreviewValidationError(
      "This preview is limited to 100 records. Reset it to start fresh.",
    );
  }
  const validated = validateValues(session.definition, values);
  return {
    ...session,
    nextId: session.nextId + 1,
    records: [
      ...session.records,
      { id: `local-${session.nextId}`, values: validated },
    ],
  };
}

export function updatePreviewRecord(
  session: PreviewSession,
  id: string,
  values: Values,
): PreviewSession {
  if (!session.records.some((record) => record.id === id)) {
    throw new PreviewValidationError(
      "This sample record is no longer available.",
    );
  }
  const validated = validateValues(session.definition, values);
  return {
    ...session,
    records: session.records.map((record) =>
      record.id === id ? { ...record, values: validated } : record,
    ),
  };
}

export function customizePreview(
  session: PreviewSession,
  title: string,
  labels: Record<string, string>,
): PreviewSession {
  if (
    Object.keys(labels).some(
      (id) => !session.definition.fields.some((field) => field.id === id),
    )
  ) {
    throw new PreviewValidationError("An unknown field cannot be customized.");
  }
  const definition = copyDefinition(session.definition);
  definition.title = boundedText(title, "App title", 80);
  definition.fields = definition.fields.map((field) => ({
    ...field,
    label: boundedText(labels[field.id] ?? field.label, "Field label", 64),
  }));
  validateDefinition(definition);
  return { ...session, definition };
}

export function resetPreviewSession(session: PreviewSession): PreviewSession {
  return createPreviewSession(session.source);
}

export function emptyValues(definition: Definition): Values {
  return Object.fromEntries(
    definition.fields.map((field) => [
      field.id,
      field.kind === "boolean" ? false : "",
    ]),
  );
}
