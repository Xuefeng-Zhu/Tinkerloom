export type Field = {
  id: string;
  label: string;
  kind: "text" | "longText" | "boolean" | "choice";
  required?: boolean;
  options?: string[];
};

export type Definition = {
  title: string;
  description: string;
  primaryFieldId: string;
  fields: Field[];
};

export type Values = Record<string, string | boolean>;
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
  fields: definition.fields.map((field) => ({
    ...field,
    ...(field.options ? { options: [...field.options] } : {}),
  })),
});

function boundedText(value: unknown, name: string, maximum: number): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new PreviewValidationError(`${name} is required.`);
  }
  const text = value.trim();
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
    if (!["text", "longText", "boolean", "choice"].includes(field.kind)) {
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
    if (typeof value !== "string") {
      throw new PreviewValidationError(`${field.label} must be text.`);
    }
    const text = value.trim();
    if (field.required && text.length === 0) {
      throw new PreviewValidationError(`${field.label} is required.`);
    }
    const maximum = field.kind === "longText" ? 4000 : 200;
    if (text.length > maximum) {
      throw new PreviewValidationError(
        `${field.label} must be ${maximum} characters or fewer.`,
      );
    }
    if (field.kind === "choice" && text && !field.options?.includes(text)) {
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
