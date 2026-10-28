import { decodeAppSpec } from "../spec/decode";
import { canonicalJson } from "../spec/schema";
import { isConfiguredView } from "../spec/bindings";
import type {
  AppSpec,
  AppearanceSpec,
  FieldSpec,
  ViewSpec,
  PageSpec,
  TabSpec,
  AutomationSpec,
  ActionSpec,
} from "../spec/types";
import { ensure } from "../runtime/errors";
import { runtimeJsonSnapshot } from "../runtime/json";

export type SemanticEdit =
  | { type: "RenameLabel"; targetId: string; label: string }
  | {
      type: "RenameField";
      collectionId: string;
      fieldId: string;
      label: string;
    }
  | {
      type: "AddField";
      collectionId: string;
      field: Omit<FieldSpec, "id">;
      viewIds?: string[];
    }
  | { type: "AddChoice"; collectionId: string; fieldId: string; choice: string }
  | { type: "AddView"; view: Omit<ViewSpec, "id"> }
  | { type: "UpdateView"; viewId: string; view: Omit<ViewSpec, "id"> }
  | {
      type: "AddPage";
      page: Omit<PageSpec, "id">;
      views?: Omit<ViewSpec, "id">[];
      tab?: Omit<TabSpec, "pageId">;
    }
  | { type: "UpdatePage"; pageId: string; page: Omit<PageSpec, "id"> }
  | { type: "ReorderPages"; pageIds: string[] }
  | { type: "SetNavigation"; entryPageId: string; tabs: TabSpec[] }
  | { type: "SetTheme"; theme: AppSpec["theme"]; icon?: AppSpec["icon"] }
  | { type: "SetAppearance"; appearance: AppearanceSpec | null }
  | { type: "ReorderView"; viewIds: string[] }
  | { type: "ProposeReminder"; reminder: Omit<AutomationSpec, "id"> }
  | {
      type: "UpdateReminder";
      reminderId: string;
      reminder: Omit<AutomationSpec, "id">;
    }
  | { type: "AddAction"; action: Omit<ActionSpec, "id"> }
  | { type: "UpdateAction"; actionId: string; action: Omit<ActionSpec, "id"> };
function find<T extends { id: string }>(items: T[], id: string): T {
  const item = items.find((v) => v.id === id);
  ensure(item, "invalid_input", `Unknown component ${id}.`);
  return item;
}
function reorder<T extends { id: string }>(items: T[], ids: string[]) {
  ensure(
    ids.length === items.length &&
      new Set(ids).size === items.length &&
      ids.every((id) => items.some((v) => v.id === id)),
    "invalid_input",
    "Ordering must include every component exactly once.",
  );
  return ids.map((id) => find(items, id));
}
export function semanticId(
  newId: () => string,
  used: Set<string>,
  prefix = "item",
): string {
  for (let tries = 0; tries < 8; tries++) {
    const id = `${prefix}_${newId().replace(/[^A-Za-z0-9_]/g, "")}`.slice(
      0,
      64,
    );
    if (/^[A-Za-z][A-Za-z0-9_]{1,63}$/.test(id) && !used.has(id)) {
      used.add(id);
      return id;
    }
  }
  throw new Error("Could not allocate a unique stable component ID.");
}
export function allSemanticIds(spec: AppSpec): Set<string> {
  return new Set([
    ...spec.collections.flatMap((c) => [
      c.id,
      ...c.fields.map((f) => f.id),
      ...c.behaviors.map((b) => b.id),
    ]),
    ...spec.views.map((v) => v.id),
    ...spec.actions.map((a) => a.id),
    ...spec.automationRequests.map((r) => r.id),
    ...(spec.navigation?.pages.map((p) => p.id) ?? []),
    ...spec.views.flatMap((v) =>
      v.type === "form" ? (v.options?.steps?.map((step) => step.id) ?? []) : [],
    ),
  ]);
}
/** Clone, atomically edit bindings, then validate the entire declaration. */
export function applySemanticEdit(
  input: AppSpec,
  edit: SemanticEdit,
  newId: () => string,
): AppSpec {
  const spec = JSON.parse(canonicalJson(decodeAppSpec(input))) as AppSpec;
  const patch = runtimeJsonSnapshot(edit) as SemanticEdit;
  const used = allSemanticIds(spec),
    allocate = (prefix: string) => semanticId(newId, used, prefix);
  const require = (capability: string) => {
    if (!spec.requires.includes(capability as never))
      spec.requires.push(capability as never);
  };
  const viewCaps = (view: ViewSpec) => {
    require(`views.${view.type}.v1`);
    if (isConfiguredView(view)) require("views.configured.v1");
    if (
      ["form", "board"].includes(view.type) &&
      Object.keys(view.options ?? {}).length
    )
      require("views.interactive.v1");
  };
  const reminderCaps = (rule: AutomationSpec) => {
    require("notifications.inApp.v1");
    if (rule.effect.type === "notifyOwner") require("notifications.owner.v1");
    if (rule.condition) require("automations.conditions.v1");
  };
  switch (patch.type) {
    case "RenameLabel": {
      if (patch.targetId === "app") {
        spec.name = patch.label;
        break;
      }
      const matches = [
        ...spec.collections,
        ...spec.collections.flatMap((c) => c.fields),
        ...spec.views,
        ...spec.actions,
        ...(spec.navigation?.pages ?? []),
      ].filter((v) => v.id === patch.targetId);
      ensure(
        matches.length === 1,
        "invalid_input",
        "Label target must identify exactly one component.",
      );
      const target = matches[0];
      if ("title" in target) target.title = patch.label;
      else target.label = patch.label;
      break;
    }
    case "RenameField":
      find(
        find(spec.collections, patch.collectionId).fields,
        patch.fieldId,
      ).label = patch.label;
      break;
    case "AddChoice": {
      const field = find(
        find(spec.collections, patch.collectionId).fields,
        patch.fieldId,
      );
      ensure(
        field.type === "choice",
        "invalid_input",
        "Choose a choice field.",
      );
      field.choices = [...(field.choices ?? []), patch.choice];
      break;
    }
    case "AddField": {
      const collection = find(spec.collections, patch.collectionId),
        field = { ...patch.field, id: allocate("field") };
      const targets =
        patch.viewIds === undefined ? null : new Set(patch.viewIds);
      if (targets) {
        ensure(
          targets.size === patch.viewIds!.length,
          "invalid_input",
          "Duplicate view binding.",
        );
        for (const id of targets) {
          const view = find(spec.views, id);
          ensure(
            view.collectionId === collection.id &&
              ["list", "table", "form", "details"].includes(view.type),
            "invalid_input",
            "New fields can bind only to list, table, form and details views in this collection.",
          );
        }
      }
      for (const view of spec.views.filter(
        (v) => v.collectionId === collection.id,
      )) {
        const implicit = !view.fieldIds?.length;
        if (targets?.has(view.id) && !implicit)
          view.fieldIds = [...view.fieldIds!, field.id];
        if (
          targets &&
          view.type === "form" &&
          view.options?.steps?.length &&
          (implicit || targets.has(view.id))
        ) {
          const step = view.options.steps[view.options.steps.length - 1];
          step.fieldIds = [...step.fieldIds, field.id];
          viewCaps(view);
        }
      }
      collection.fields.push(field);
      if (field.type === "image") require("fields.image.v1");
      break;
    }
    case "AddView": {
      const view = { ...patch.view, id: allocate("view") } as ViewSpec;
      spec.views.push(view);
      viewCaps(view);
      break;
    }
    case "UpdateView": {
      ensure(
        !Object.hasOwn(patch.view, "id"),
        "invalid_input",
        "View identity cannot change.",
      );
      const index = spec.views.indexOf(find(spec.views, patch.viewId));
      spec.views[index] = { ...patch.view, id: patch.viewId } as ViewSpec;
      viewCaps(spec.views[index]);
      break;
    }
    case "AddPage": {
      ensure(
        !Object.hasOwn(patch.page, "id"),
        "invalid_input",
        "Page identity is allocated by the platform.",
      );
      const views = (patch.views ?? []).map(
        (view) => ({ ...view, id: allocate("view") }) as ViewSpec,
      );
      views.forEach(viewCaps);
      spec.views.push(...views);
      const page = {
        ...patch.page,
        id: allocate("page"),
        viewIds: [...patch.page.viewIds, ...views.map((v) => v.id)],
      };
      if (!spec.navigation)
        spec.navigation = { entryPageId: page.id, pages: [], tabs: [] };
      spec.navigation.pages.push(page);
      if (patch.tab)
        spec.navigation.tabs.push({ ...patch.tab, pageId: page.id });
      else if (spec.navigation.pages.length === 1)
        spec.navigation.tabs.push({
          pageId: page.id,
          label: page.title.slice(0, 40),
          icon: "spark",
        });
      require("navigation.v1");
      break;
    }
    case "UpdatePage": {
      ensure(
        spec.navigation && !Object.hasOwn(patch.page, "id"),
        "invalid_input",
        "Choose an existing page and preserve its identity.",
      );
      const index = spec.navigation.pages.indexOf(
        find(spec.navigation.pages, patch.pageId),
      );
      spec.navigation.pages[index] = { ...patch.page, id: patch.pageId };
      break;
    }
    case "ReorderPages":
      ensure(spec.navigation, "invalid_input", "Add navigation first.");
      spec.navigation.pages = reorder(spec.navigation.pages, patch.pageIds);
      break;
    case "SetNavigation":
      ensure(spec.navigation, "invalid_input", "Add navigation first.");
      spec.navigation.entryPageId = patch.entryPageId;
      spec.navigation.tabs = patch.tabs;
      break;
    case "SetTheme":
      spec.theme = patch.theme;
      if (patch.icon) spec.icon = patch.icon;
      break;
    case "SetAppearance":
      if (patch.appearance) spec.appearance = patch.appearance;
      else delete spec.appearance;
      break;
    case "ReorderView":
      spec.views = reorder(spec.views, patch.viewIds);
      break;
    case "ProposeReminder": {
      const rule = { ...patch.reminder, id: allocate("rule") };
      spec.automationRequests.push(rule);
      reminderCaps(rule);
      break;
    }
    case "UpdateReminder": {
      ensure(
        !Object.hasOwn(patch.reminder, "id"),
        "invalid_input",
        "Reminder identity cannot change.",
      );
      const index = spec.automationRequests.indexOf(
        find(spec.automationRequests, patch.reminderId),
      );
      spec.automationRequests[index] = {
        ...patch.reminder,
        id: patch.reminderId,
      };
      reminderCaps(spec.automationRequests[index]);
      break;
    }
    case "AddAction": {
      const action = { ...patch.action, id: allocate("action") };
      spec.actions.push(action);
      require(action.capability);
      break;
    }
    case "UpdateAction": {
      ensure(
        !Object.hasOwn(patch.action, "id"),
        "invalid_input",
        "Action identity cannot change.",
      );
      const index = spec.actions.indexOf(find(spec.actions, patch.actionId));
      spec.actions[index] = { ...patch.action, id: patch.actionId };
      require(patch.action.capability);
      break;
    }
  }
  if (
    [
      "SetAppearance",
      "AddView",
      "UpdateView",
      "AddPage",
      "UpdatePage",
    ].includes(patch.type)
  ) {
    const appearance =
      !!spec.appearance ||
      spec.views.some(
        (v) => v.type === "banner" && v.options?.imagePlacement !== undefined,
      );
    const layouts =
      spec.navigation?.pages.some((p) => p.layout !== undefined) ?? false;
    for (const [cap, needed] of [
      ["appearance.v1", appearance],
      ["navigation.layouts.v1", layouts],
    ] as const) {
      spec.requires = spec.requires.filter((v) => v !== cap);
      if (needed) require(cap);
    }
  }
  return decodeAppSpec(spec);
}
export { presentationFingerprint } from "../runtime/preview";
