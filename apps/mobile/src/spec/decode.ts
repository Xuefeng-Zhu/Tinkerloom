import { AppSpecError, requireSpec } from "./errors";
import { assertSchema, canonicalJson, jsonSnapshot, utf8Bytes } from "./schema";
import {
  actionsForView,
  CONTENT_VIEW_TYPES,
  editableFieldsForView,
  fieldsForView,
  getAction,
  getBehavior,
  getCollection,
  getField,
  getPage,
  getView,
  isConfiguredView,
  RICH_VIEW_TYPES,
} from "./bindings";
import { nonblank, normalizeFieldValue, validateRecordQuery } from "./values";
import { LIMITS } from "./types";
import type {
  AppSpec,
  Capability,
  CollectionSpec,
  FieldType,
  FormControl,
  ViewSpec,
} from "./types";

type ObjectValue = Record<string, unknown>;
const unique = (values: readonly string[], path: string) =>
  requireSpec(
    new Set(values).size === values.length,
    path,
    "Duplicate stable IDs or values",
  );
const object = (value: unknown) => value as ObjectValue;

/** Match Dart toJson omission/default rules, without resolving display defaults. */
function normalize(source: ObjectValue): AppSpec {
  const result = { ...source };
  result.collections = (source.collections as ObjectValue[]).map(
    (collection) => ({
      ...collection,
      fields: (collection.fields as ObjectValue[]).map((field) => {
        const next = { ...field };
        if (!(next.choices as unknown[] | undefined)?.length)
          delete next.choices;
        return next;
      }),
      behaviors: ((collection.behaviors ?? []) as ObjectValue[]).map(
        (behavior) => {
          const next = { ...behavior };
          if (!Object.keys(object(next.transitions ?? {})).length)
            delete next.transitions;
          return next;
        },
      ),
    }),
  );
  result.views = (source.views as ObjectValue[]).map((view) => {
    const next = {
      ...view,
      label: view.label ?? view.id,
      actionIds: view.actionIds ?? [],
    } as ObjectValue;
    for (const key of ["fieldIds", "filterFieldIds"])
      if (!(next[key] as unknown[] | undefined)?.length) delete next[key];
    if (!Object.keys(object(next.options ?? {})).length) delete next.options;
    return next;
  });
  if (source.navigation)
    result.navigation = {
      ...object(source.navigation),
      pages: (object(source.navigation).pages as ObjectValue[]).map((page) => {
        const next = { ...page };
        if (next.showDate === false) delete next.showDate;
        return next;
      }),
    };
  if (source.appearance)
    result.appearance = {
      ...object(source.appearance),
      ...(object(source.appearance).accentColor === undefined
        ? {}
        : {
            accentColor: (
              object(source.appearance).accentColor as string
            ).toUpperCase(),
          }),
    };
  return result as unknown as AppSpec;
}

function validateCollection(collection: CollectionSpec): void {
  const path = `collections.${collection.id}`;
  nonblank(collection.label, path);
  unique(
    collection.fields.map((field) => field.id),
    `${path}.fields`,
  );
  unique(
    collection.behaviors.map((behavior) => behavior.id),
    `${path}.behaviors`,
  );
  requireSpec(
    collection.behaviors.filter((behavior) => behavior.type === "capacity.v1")
      .length <= 1,
    path,
    "Only one capacity pool per collection is supported",
  );
  for (const field of collection.fields) {
    nonblank(field.label, `${path}.${field.id}`);
    const choices = field.choices ?? [];
    unique(choices, `${path}.${field.id}.choices`);
    for (const choice of choices)
      nonblank(choice, `${path}.${field.id}.choices`, 80);
    requireSpec(
      field.type === "choice" ? choices.length > 0 : choices.length === 0,
      `${path}.${field.id}`,
      "Only choice fields declare nonempty choices",
    );
  }
  for (const behavior of collection.behaviors) {
    const transitions = behavior.transitions ?? {};
    for (const targets of Object.values(transitions))
      for (const target of targets) nonblank(target, path);
    if (behavior.type === "capacity.v1") {
      requireSpec(
        behavior.fieldId === undefined && Object.keys(transitions).length === 0,
        path,
        "Capacity is typed state, not a payload field",
      );
      continue;
    }
    const field = getField(collection, behavior.fieldId ?? "");
    if (behavior.type === "assignment.v1")
      requireSpec(
        field.type === "member",
        path,
        "Assignment needs a member field",
      );
    if (behavior.type === "workflow.v1") {
      requireSpec(
        field.type === "choice" && Object.keys(transitions).length > 0,
        path,
        "Workflow needs a choice field and transitions",
      );
      for (const [state, targets] of Object.entries(transitions)) {
        requireSpec(
          field.choices?.includes(state) &&
            targets.every((target) => field.choices?.includes(target)),
          path,
          "Unknown workflow transition status",
        );
      }
    }
  }
}

function validateControls(
  spec: AppSpec,
  view: Extract<ViewSpec, { type: "form" }>,
  collection: CollectionSpec,
): void {
  const options = view.options ?? {};
  const controls = options.controls ?? [],
    steps = options.steps;
  const editable = new Set(
    editableFieldsForView(spec, view).map((field) => field.id),
  );
  unique(
    controls.map((control) => control.fieldId),
    `${view.id}.controls`,
  );
  const types: Record<FormControl["control"], FieldType[]> = {
    text: ["text"],
    multiline: ["text"],
    switch: ["boolean"],
    checkbox: ["boolean"],
    select: ["choice", "member"],
    segmented: ["choice"],
    slider: ["integer", "number"],
    stepper: ["integer", "number"],
    rating: ["integer"],
    dateTime: ["timestamp"],
    imageUpload: ["image"],
  };
  for (const control of controls) {
    const field = getField(collection, control.fieldId);
    requireSpec(
      editable.has(field.id),
      view.id,
      "Control must reference an editable visible field",
    );
    requireSpec(
      types[control.control].includes(field.type),
      view.id,
      "Control and field types do not match",
    );
    if (control.hint !== undefined) nonblank(control.hint, view.id, 500);
    if (control.control === "segmented")
      requireSpec(
        (field.choices?.length ?? 0) <= 6,
        view.id,
        "Segmented controls support at most six choices",
      );
    const numeric = ["slider", "stepper", "rating"].includes(control.control);
    for (const key of ["min", "max", "step"] as const) {
      if (control[key] !== undefined)
        requireSpec(
          numeric && Number.isFinite(control[key]),
          view.id,
          "Numeric bounds need a numeric control",
        );
      if (field.type === "integer" && control[key] !== undefined)
        requireSpec(
          Number.isInteger(control[key]),
          view.id,
          "Integer controls need integral bounds and steps",
        );
    }
    if (control.control === "slider" || control.control === "stepper") {
      const { min, max, step } = control;
      requireSpec(
        typeof min === "number" &&
          typeof max === "number" &&
          typeof step === "number" &&
          min < max &&
          step > 0 &&
          step <= max - min &&
          Number.isFinite(max - min) &&
          Number.isFinite((max - min) / step),
        view.id,
        "Sliders and steppers need finite min, max and positive step",
      );
    }
    if (control.control === "rating")
      requireSpec(
        control.min === undefined &&
          control.max === undefined &&
          control.step === undefined,
        view.id,
        "Ratings use one to five without custom bounds",
      );
    if (field.type === "integer" || field.type === "number")
      for (const key of ["min", "max"] as const)
        if (control[key] !== undefined)
          normalizeFieldValue(field, control[key], view.id);
  }
  if (steps !== undefined) {
    unique(
      steps.map((step) => step.id),
      `${view.id}.steps`,
    );
    const all = steps.flatMap((step) => step.fieldIds);
    unique(all, `${view.id}.steps.fields`);
    for (const step of steps) {
      nonblank(step.title, view.id);
      for (const id of step.fieldIds) getField(collection, id);
    }
    requireSpec(
      all.length === editable.size && all.every((id) => editable.has(id)),
      view.id,
      "Steps must cover every editable field exactly once",
    );
  }
}

function validateRichView(spec: AppSpec, view: ViewSpec): void {
  const path = `views.${view.id}`;
  if (CONTENT_VIEW_TYPES.has(view.type)) {
    requireSpec(
      view.titleFieldId === undefined &&
        view.groupByFieldId === undefined &&
        !view.fieldIds?.length &&
        !view.filterFieldIds?.length &&
        view.actionIds.length === 0 &&
        view.query === undefined &&
        view.dateFilter === undefined &&
        view.detailPageId === undefined &&
        view.formPageId === undefined &&
        view.presentation === undefined,
      path,
      "Content blocks cannot bind records, actions or queries",
    );
    if (view.type === "banner") {
      const options = view.options!;
      nonblank(options.title, path);
      if (options.body !== undefined) nonblank(options.body, path, 2048);
      if (options.imageAssetId !== undefined) {
        requireSpec(
          /^[A-Za-z0-9_-]{1,128}$/.exec(options.imageAssetId)?.[0] ===
            options.imageAssetId && options.imageAlt !== undefined,
          path,
          "A banner image needs a private asset ID and description",
        );
      }
      if (options.imageAlt !== undefined) nonblank(options.imageAlt, path, 500);
      if (options.targetPageId !== undefined)
        requireSpec(
          spec.navigation?.tabs.some(
            (tab) => tab.pageId === options.targetPageId,
          ),
          path,
          "Banner destinations must be app tabs",
        );
    }
    if (view.type === "richText") nonblank(view.options!.markdown, path, 8192);
    if (view.type === "deviceInfo") unique(view.options!.fields, path);
    return;
  }
  const collection = getCollection(spec, view.collectionId!);
  const typed = (id: string | undefined, types: FieldType[]) => {
    const field = getField(collection, id ?? "");
    requireSpec(
      types.includes(field.type),
      path,
      "Incompatible field binding type",
    );
    return field;
  };
  if (view.type === "calendar" || view.type === "timeline")
    typed(view.options!.dateFieldId, ["timestamp"]);
  if (view.type === "imageCards" || view.type === "gallery") {
    typed(view.options!.imageFieldId, ["image"]);
    if (view.options?.captionFieldId !== undefined)
      typed(view.options.captionFieldId, ["text"]);
  }
  if (view.type === "metric" || view.type === "chart") {
    const options = view.options!;
    if (options.metric === "count")
      requireSpec(
        options.valueFieldId === undefined,
        path,
        "Count takes no numeric value field",
      );
    else typed(options.valueFieldId, ["integer", "number"]);
    if (view.type === "metric")
      requireSpec(
        view.groupByFieldId === undefined,
        path,
        "Metric tiles cannot group records",
      );
    else {
      const chart = view.options!;
      const dates = chart.dateFieldId !== undefined;
      if (dates) {
        typed(chart.dateFieldId, ["timestamp"]);
        requireSpec(
          view.groupByFieldId === undefined && chart.bucket !== undefined,
          path,
          "Date charts use date buckets instead of choice groups",
        );
      } else {
        typed(view.groupByFieldId, ["choice"]);
        requireSpec(
          chart.bucket === undefined && chart.periods === undefined,
          path,
          "Only date charts use buckets",
        );
      }
      if (chart.style === "line")
        requireSpec(dates, path, "Line charts need date buckets");
      if (chart.style === "donut")
        requireSpec(
          !dates && chart.metric === "count",
          path,
          "Donuts show choice counts",
        );
    }
  }
  if (view.type === "form") validateControls(spec, view, collection);
  if (
    view.type === "checklist" ||
    (view.type === "board" && Object.keys(view.options ?? {}).length > 0)
  ) {
    const checklist = view.type === "checklist";
    const id = checklist ? view.options!.fieldId : view.groupByFieldId;
    const actionId = checklist
      ? view.options!.actionId
      : view.options!.moveActionId;
    const field = getField(collection, id ?? ""),
      action = getAction(spec, actionId ?? "");
    requireSpec(
      action.collectionId === collection.id &&
        view.actionIds.includes(action.id),
      path,
      "The component action must be bound to the same collection and view",
    );
    if (view.type === "board")
      requireSpec(
        view.options?.draggable === true,
        path,
        "Interactive boards need draggable true",
      );
    if (checklist && field.type === "boolean")
      requireSpec(
        action.capability === "records.patch.v1" &&
          view.options!.checkedValue === undefined &&
          view.options!.uncheckedValue === undefined,
        path,
        "Boolean checklists need a record patch action",
      );
    else {
      requireSpec(
        field.type === "choice" &&
          action.capability === "workflow.transition.v1" &&
          action.behaviorId !== undefined,
        path,
        "Workflow components need a choice field and transition action",
      );
      const behavior = getBehavior(collection, action.behaviorId);
      requireSpec(
        behavior.type === "workflow.v1" && behavior.fieldId === field.id,
        path,
        "The component must bind its workflow field",
      );
      if (view.type === "checklist") {
        const checked = view.options!.checkedValue,
          unchecked = view.options!.uncheckedValue;
        const targets = (key: string) =>
          Object.hasOwn(behavior.transitions ?? {}, key)
            ? behavior.transitions![key]
            : [];
        requireSpec(
          typeof checked === "string" &&
            typeof unchecked === "string" &&
            checked !== unchecked &&
            field.choices?.length === 2 &&
            field.choices.includes(checked) &&
            field.choices.includes(unchecked) &&
            targets(checked).includes(unchecked) &&
            targets(unchecked).includes(checked),
          path,
          "Workflow checklists need two explicit reversible states",
        );
      }
    }
  }
}

export function validateSemanticReferences(spec: AppSpec): void {
  nonblank(spec.name, "name", 80);
  unique(
    spec.collections.map((entry) => entry.id),
    "collections",
  );
  unique(
    spec.views.map((entry) => entry.id),
    "views",
  );
  unique(
    spec.actions.map((entry) => entry.id),
    "actions",
  );
  unique(
    spec.automationRequests.map((entry) => entry.id),
    "automations",
  );
  for (const collection of spec.collections) validateCollection(collection);
  if (spec.navigation) {
    const navigation = spec.navigation;
    unique(
      navigation.pages.map((page) => page.id),
      "navigation.pages",
    );
    unique(
      navigation.tabs.map((tab) => tab.pageId),
      "navigation.tabs",
    );
    requireSpec(
      navigation.tabs.some((tab) => tab.pageId === navigation.entryPageId),
      "navigation.entryPageId",
      "Entry page must be an app tab",
    );
    for (const tab of navigation.tabs) {
      getPage(spec, tab.pageId);
      nonblank(tab.label, "navigation.tabs", 40);
    }
    for (const page of navigation.pages) {
      nonblank(page.title, page.id);
      unique(page.viewIds, page.id);
      for (const id of page.viewIds) getView(spec, id);
    }
  }
  const needed = new Set<string>();
  if (spec.collections.length) needed.add("collections.v1");
  if (spec.navigation) needed.add("navigation.v1");
  if (spec.appearance) needed.add("appearance.v1");
  if (spec.navigation?.pages.some((page) => page.layout !== undefined))
    needed.add("navigation.layouts.v1");
  for (const collection of spec.collections) {
    collection.behaviors.forEach((behavior) => needed.add(behavior.type));
    if (collection.fields.some((field) => field.type === "image"))
      needed.add("fields.image.v1");
  }
  for (const view of spec.views) {
    const path = `views.${view.id}`;
    nonblank(view.label, path);
    needed.add(`views.${view.type}.v1`);
    const configured = isConfiguredView(view);
    if (configured) needed.add("views.configured.v1");
    if (view.type === "banner" && view.options?.imagePlacement !== undefined)
      needed.add("appearance.v1");
    if (
      RICH_VIEW_TYPES.has(view.type) ||
      Object.keys(view.options ?? {}).length > 0
    ) {
      requireSpec(spec.navigation, path, "Rich components need app navigation");
      validateRichView(spec, view);
    }
    if (
      (view.type === "form" || view.type === "board") &&
      Object.keys(view.options ?? {}).length > 0
    )
      needed.add("views.interactive.v1");
    if (CONTENT_VIEW_TYPES.has(view.type)) continue;
    const collection = getCollection(spec, view.collectionId!);
    if (view.titleFieldId !== undefined)
      getField(collection, view.titleFieldId);
    if (view.groupByFieldId !== undefined) {
      const field = getField(collection, view.groupByFieldId);
      if ((configured || spec.navigation) && view.type === "summary")
        requireSpec(
          field.type === "choice",
          path,
          "Grouped summaries need a choice field",
        );
    }
    unique(view.fieldIds ?? [], path);
    unique(view.filterFieldIds ?? [], path);
    for (const id of view.fieldIds ?? []) getField(collection, id);
    for (const id of view.filterFieldIds ?? [])
      requireSpec(
        getField(collection, id).type === "choice",
        path,
        "View filters need choice fields",
      );
    if (view.query) validateRecordQuery(collection, view.query);
    if (view.dateFilter)
      requireSpec(
        getField(collection, view.dateFilter.fieldId).type === "timestamp",
        path,
        "Relative dates need a timestamp field",
      );
    const search =
      view.type !== "summary" &&
      Boolean(view.filterFieldIds?.length) &&
      view.titleFieldId !== undefined;
    if (search)
      requireSpec(
        getField(collection, view.titleFieldId!).type === "text",
        path,
        "Search needs a text title field",
      );
    const relative = view.dateFilter
      ? view.dateFilter.period === "today"
        ? 2
        : 1
      : 0;
    const interactive =
      view.type === "summary"
        ? 0
        : (view.filterFieldIds?.length ?? 0) + (search ? 1 : 0);
    const component =
      view.type === "calendar"
        ? 2
        : view.type === "timeline" &&
            !getField(collection, view.options!.dateFieldId).required
          ? 1
          : 0;
    requireSpec(
      (view.query?.filters?.length ?? 0) + relative + interactive + component <=
        8,
      path,
      "Too many combined filters, including interactive controls",
    );
    for (const [destination, type] of [
      [view.detailPageId, "details"],
      [view.formPageId, "form"],
    ] as const) {
      if (destination === undefined) continue;
      const page = getPage(spec, destination),
        targets = page.viewIds
          .map((id) => getView(spec, id))
          .filter(
            (target) =>
              target.type === type && target.collectionId === collection.id,
          );
      requireSpec(
        targets.length > 0,
        path,
        "Navigation destination needs a matching collection view",
      );
      if (type === "form")
        for (const action of actionsForView(spec, view).filter(
          (action) =>
            action.capability === "records.create.v1" ||
            action.capability === "records.patch.v1",
        ))
          requireSpec(
            targets.some((target) =>
              actionsForView(spec, target).some(
                (bound) =>
                  bound.collectionId === collection.id &&
                  bound.capability === action.capability,
              ),
            ),
            path,
            "Destination form must support the source record action",
          );
    }
    if (view.type === "form") {
      requireSpec(
        actionsForView(spec, view).some(
          (action) => action.capability === "records.create.v1",
        ),
        path,
        "Forms need a record creation action",
      );
      if (spec.navigation && view.fieldIds?.length) {
        const shown = new Set(
          fieldsForView(spec, view).map((field) => field.id),
        );
        const managed = new Set(
          collection.behaviors
            .filter((behavior) => behavior.type === "workflow.v1")
            .map((behavior) => behavior.fieldId),
        );
        requireSpec(
          collection.fields.every(
            (field) =>
              !field.required || managed.has(field.id) || shown.has(field.id),
          ),
          path,
          "Create form omits a required field",
        );
      }
    }
    if (view.type === "action")
      requireSpec(
        view.actionIds.length > 0,
        path,
        "Action views need an action",
      );
    if (view.type === "board")
      requireSpec(
        view.groupByFieldId !== undefined &&
          getField(collection, view.groupByFieldId).type === "choice",
        path,
        "Boards need a choice field",
      );
    if (view.type === "capacity")
      requireSpec(
        collection.behaviors.some(
          (behavior) => behavior.type === "capacity.v1",
        ),
        path,
        "Capacity views need capacity behavior",
      );
    for (const action of actionsForView(spec, view))
      requireSpec(
        action.collectionId === collection.id,
        path,
        "View action belongs to another collection",
      );
  }
  for (const action of spec.actions) {
    needed.add(action.capability);
    nonblank(action.label, action.id);
    const collection = getCollection(spec, action.collectionId);
    const expected = action.capability.startsWith("capacity.")
      ? "capacity.v1"
      : action.capability.startsWith("workflow.")
        ? "workflow.v1"
        : action.capability.startsWith("assignment.")
          ? "assignment.v1"
          : null;
    if (expected)
      requireSpec(
        action.behaviorId !== undefined &&
          collection.behaviors.some(
            (behavior) =>
              behavior.id === action.behaviorId && behavior.type === expected,
          ),
        action.id,
        "Action must reference its declared behavior in the same collection",
      );
    else
      requireSpec(
        action.behaviorId === undefined,
        action.id,
        "Record actions do not bind behaviors",
      );
  }
  for (const rule of spec.automationRequests) {
    needed.add("notifications.inApp.v1");
    const collection = getCollection(spec, rule.trigger.collectionId);
    requireSpec(
      getField(collection, rule.trigger.fieldId).type === "timestamp",
      rule.id,
      "Reminders need a timestamp field",
    );
    if (rule.condition) {
      needed.add("automations.conditions.v1");
      const field = getField(collection, rule.condition.fieldId);
      nonblank(rule.condition.value, rule.id, 80);
      requireSpec(
        field.type === "choice" &&
          field.choices?.includes(rule.condition.value),
        rule.id,
        "Reminder condition needs a declared choice",
      );
    }
    if (rule.effect.type === "notifyOwner") {
      needed.add("notifications.owner.v1");
      requireSpec(
        spec.policyPresetRequest === "personalTracker.v1",
        rule.id,
        "Owner reminders need personal-tracker policy",
      );
    } else {
      const behavior =
        rule.effect.type === "notifyActiveClaimants"
          ? "capacity.v1"
          : "assignment.v1";
      requireSpec(
        collection.behaviors.some((entry) => entry.type === behavior),
        rule.id,
        "Reminder recipient requires a matching behavior",
      );
    }
  }
  for (const page of spec.navigation?.pages ?? []) {
    const views = page.viewIds.map((id) => getView(spec, id));
    if (page.primaryActionId !== undefined) {
      const action = getAction(spec, page.primaryActionId);
      requireSpec(
        action.capability === "records.create.v1" &&
          views.some(
            (view) =>
              view.actionIds.includes(action.id) &&
              (view.type === "form" || view.formPageId !== undefined),
          ),
        page.id,
        "Primary action needs a reachable bound creation form",
      );
    }
    if (views.some((view) => view.type === "form" || view.type === "details"))
      requireSpec(
        views.length === 1 &&
          !spec.navigation!.tabs.some((tab) => tab.pageId === page.id),
        page.id,
        "Record forms and details need dedicated non-tab pages",
      );
  }
  const missing = [...needed].filter(
    (capability) => !spec.requires.includes(capability as Capability),
  );
  requireSpec(
    missing.length === 0,
    "requires",
    `Missing required capabilities: ${missing.join(", ")}`,
    "missing_capability",
  );
}

export function decodeAppSpec(input: unknown): AppSpec {
  let value: unknown = input;
  if (typeof input === "string") {
    requireSpec(
      utf8Bytes(input) <= LIMITS.definitionBytes,
      "$",
      "Definition is too large",
      "definition_size",
    );
    try {
      value = JSON.parse(input);
    } catch {
      throw new AppSpecError(
        "invalid_json",
        "$",
        "Definition must be valid JSON",
      );
    }
  }
  const snapshot = jsonSnapshot(value);
  assertSchema(snapshot);
  const spec = normalize(object(snapshot));
  validateSemanticReferences(spec);
  return spec;
}
export function tryDecodeAppSpec(
  input: unknown,
): { ok: true; spec: AppSpec } | { ok: false; error: AppSpecError } {
  try {
    return { ok: true, spec: decodeAppSpec(input) };
  } catch (error) {
    return {
      ok: false,
      error:
        error instanceof AppSpecError
          ? error
          : new AppSpecError(
              "invalid_appspec",
              "$",
              "This app definition is unavailable or unsupported",
            ),
    };
  }
}
/** Backend candidate hashes remain authoritative; this is deterministic JSON, not a client hash. */
export function canonicalAppSpec(input: AppSpec | unknown): string {
  return canonicalJson(decodeAppSpec(input));
}
