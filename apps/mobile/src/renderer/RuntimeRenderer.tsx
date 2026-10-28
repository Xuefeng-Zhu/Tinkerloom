import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { Modal, ScrollView, View, useWindowDimensions } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import type { RuntimeController } from "../runtime/controller";
import type {
  DeviceBridge,
  RuntimeLocation,
  RuntimeRecord,
} from "../runtime/types";
import type { UtilityTimerController } from "../runtime/timer";
import type { ViewSpec, ViewSpecOf } from "../spec/types";
import { RendererContext } from "./context";
import { pageRows, resolveAppearance } from "./appearance";
import { Body, Button, Notice, Panel, Row } from "./primitives";
import { DetailsView, SemanticView } from "./views";
import { RecordForm } from "./form";

interface EditorTarget {
  view: ViewSpecOf<"form">;
  record?: RuntimeRecord;
}
export interface RuntimeRendererProps {
  controller: RuntimeController;
  timers?: UtilityTimerController;
  device?: DeviceBridge;
  onExit?: () => void;
  onLocationChange?: (location: RuntimeLocation) => void;
}
/** A semantic host. Its controller/command lifetime is owned by the app scope. */
export function RuntimeRenderer(props: RuntimeRendererProps) {
  return <RuntimeRendererScope key={props.controller.scopeId} {...props} />;
}
function RuntimeRendererScope({
  controller,
  timers,
  device,
  onExit,
  onLocationChange,
}: RuntimeRendererProps) {
  const state = useSyncExternalStore(
      controller.subscribe,
      controller.getSnapshot,
      controller.getSnapshot,
    ),
    spec = controller.adapter.spec,
    theme = useMemo(() => resolveAppearance(spec), [spec]),
    dimensions = useWindowDimensions();
  const [editor, setEditor] = useState<EditorTarget | null>(null),
    [details, setDetails] = useState<{
      view: ViewSpec;
      record: RuntimeRecord;
    } | null>(() => {
      const current = controller.getSnapshot();
      const record = current.record;
      if (
        !record ||
        current.location.editing ||
        controller.views.some(
          (view) =>
            view.type === "details" &&
            view.collectionId === record.collectionId,
        )
      )
        return null;
      const view =
        controller.views.find(
          (view) =>
            view.collectionId === record.collectionId && view.type !== "form",
        ) ??
        controller.adapter.spec.views.find(
          (view) =>
            view.collectionId === record.collectionId && view.type !== "form",
        );
      return view ? { view, record } : null;
    }),
    [leave, setLeave] = useState<(() => void) | null>(null);
  useEffect(() => {
    void controller.refresh();
  }, [controller]);
  useEffect(() => {
    onLocationChange?.(state.location);
  }, [state.location, onLocationChange]);
  const guard = (action: () => void) => {
    if (state.pending) return;
    if (state.dirty) setLeave(() => action);
    else action();
  };
  const navigate = (location: RuntimeLocation) =>
    guard(() => {
      controller.setDirty(false);
      setEditor(null);
      setDetails(null);
      controller.navigate(location, true);
    });
  const openRecord = (view: ViewSpec, record: RuntimeRecord) => {
    if (view.detailPageId)
      navigate({ pageId: view.detailPageId, recordId: record.id });
    else
      guard(() => {
        setEditor(null);
        controller.focusRecord(record);
        setDetails({ view, record });
      });
  };
  const edit = (view: ViewSpec, record?: RuntimeRecord) => {
    if (view.formPageId) {
      navigate({
        pageId: view.formPageId,
        ...(record ? { recordId: record.id, editing: true } : {}),
      });
      return;
    }
    guard(() => {
      setDetails(null);
      if (record) controller.focusRecord(record);
      setEditor({
        view: {
          id: `editor_${view.id}`,
          type: "form",
          label: record ? "Edit record" : "New record",
          collectionId: view.collectionId!,
          actionIds: view.actionIds,
          ...(view.fieldIds ? { fieldIds: view.fieldIds } : {}),
        },
        record,
      });
    });
  };
  const closeOverlay = () =>
    guard(() => {
      controller.setDirty(false);
      controller.dismissRecord();
      setEditor(null);
      setDetails(null);
    });
  const page = spec.navigation?.pages.find(
      (item) => item.id === state.location.pageId,
    ),
    rows = pageRows(
      page,
      controller.views,
      Math.min(dimensions.width, 1200) - 32,
      dimensions.fontScale,
    ),
    primary = spec.actions.find(
      (action) => action.id === page?.primaryActionId,
    ),
    primaryView = primary
      ? controller.views.find(
          (view) =>
            view.actionIds.includes(primary.id) &&
            (view.type === "form" || view.formPageId !== undefined),
        )
      : undefined;
  const context = {
    controller,
    state,
    theme,
    navigate,
    openRecord,
    edit,
    timers,
    device,
  };
  if (state.accessDenied)
    return (
      <RendererContext.Provider value={context}>
        <SafeAreaView
          style={{ flex: 1, padding: 24, backgroundColor: theme.canvas }}
        >
          <Panel title="Access needs to be checked">
            <Notice error>
              {state.error?.message ?? "Your access changed."}
            </Notice>
            <Body>
              Cached records and editors have been hidden. Reopen this app to
              load a fresh authorized version.
            </Body>
            {onExit ? <Button onPress={onExit}>Close app</Button> : null}
          </Panel>
        </SafeAreaView>
      </RendererContext.Provider>
    );
  return (
    <RendererContext.Provider value={context}>
      <SafeAreaView style={{ flex: 1, backgroundColor: theme.canvas }}>
        <ScrollView
          key={state.location.pageId}
          contentOffset={{
            x: 0,
            y: controller.scrollFor(state.location.pageId),
          }}
          scrollEventThrottle={100}
          onScroll={(event) =>
            controller.rememberScroll(
              state.location.pageId,
              event.nativeEvent.contentOffset.y,
            )
          }
          contentContainerStyle={{
            padding: 16,
            gap: 16,
            maxWidth: 1232,
            width: "100%",
            alignSelf: "center",
          }}
          keyboardShouldPersistTaps="handled"
        >
          <Row>
            {onExit ? (
              <Button
                subtle
                disabled={Boolean(state.pending)}
                onPress={() => guard(onExit)}
              >
                Close app
              </Button>
            ) : null}
            {state.history.length ? (
              <Button
                subtle
                disabled={Boolean(state.pending)}
                onPress={() =>
                  guard(() => {
                    controller.setDirty(false);
                    controller.back(true);
                  })
                }
              >
                Back
              </Button>
            ) : null}
            <View style={{ flex: 1, minWidth: 160 }}>
              <Body heading>{spec.name}</Body>
              <Body muted>{page?.title ?? "Mini app"}</Body>
            </View>
            <Button
              subtle
              disabled={state.dirty || Boolean(state.pending) || state.loading}
              onPress={() => void controller.refresh()}
            >
              Refresh
            </Button>
          </Row>
          {controller.adapter.preview ? (
            <Notice>
              Isolated preview · synthetic records, members, images, and
              reminder examples. Changes stay in this preview.
            </Notice>
          ) : null}
          {controller.adapter.archived ? (
            <Notice>This app is archived. Records are read only.</Notice>
          ) : null}
          {!controller.writeAvailable ? (
            <Notice>
              This host has not connected durable command recovery. Live record
              changes are unavailable.
            </Notice>
          ) : null}
          {page?.showDate ? (
            <Body>
              {new Date().toLocaleDateString(undefined, {
                weekday: "long",
                year: "numeric",
                month: "long",
                day: "numeric",
              })}
            </Body>
          ) : null}
          {spec.navigation ? (
            <Row>
              {spec.navigation.tabs.map((tab) => (
                <Button
                  key={tab.pageId}
                  subtle
                  selected={state.location.pageId === tab.pageId}
                  disabled={Boolean(state.pending)}
                  onPress={() => navigate({ pageId: tab.pageId })}
                >
                  {tab.label}
                </Button>
              ))}
            </Row>
          ) : null}
          {primary && primaryView ? (
            <Button
              disabled={
                Boolean(state.pending) ||
                !controller.writeAvailable ||
                !controller.adapter.permits(primary)
              }
              onPress={() => edit(primaryView)}
            >
              {primary.label}
            </Button>
          ) : null}
          {state.pending ? (
            <Panel
              title={
                state.pending.status === "sending"
                  ? "Saving your change…"
                  : state.pending.status === "uncertain"
                    ? "Outcome not confirmed"
                    : "Change could not be saved"
              }
            >
              <Notice error={state.pending.status !== "sending"}>
                {state.pending.error?.message ??
                  "Keep this app open while the original operation is checked."}
              </Notice>
              {state.pending.status === "uncertain" ? (
                <Button onPress={() => void controller.retry()}>
                  Retry same change
                </Button>
              ) : null}
              {state.pending.status === "failed" ? (
                <Button subtle onPress={() => controller.acknowledgeFailure()}>
                  Review values
                </Button>
              ) : null}
              <Body muted>
                Your original values are retained. Resolve this save before
                making another change or leaving the app.
              </Body>
            </Panel>
          ) : null}
          {state.error && !state.pending ? (
            <Notice error>{state.error.message}</Notice>
          ) : null}
          {state.outcome ? <Notice>{state.outcome.message}</Notice> : null}
          {rows.map((row, index) => (
            <View
              key={row.map((view) => view.id).join(":")}
              style={{
                flexDirection: row.length > 1 ? "row" : "column",
                alignItems: "stretch",
                gap: 16,
              }}
            >
              {row.map((view) => (
                <View key={view.id} style={{ flex: 1, minWidth: 0 }}>
                  <SemanticView view={view} />
                </View>
              ))}
            </View>
          ))}
        </ScrollView>
        <Modal
          visible={Boolean(editor || details)}
          transparent
          animationType="fade"
          onRequestClose={closeOverlay}
        >
          <SafeAreaView
            style={{
              flex: 1,
              backgroundColor: "#00000066",
              padding: 16,
              justifyContent: "center",
            }}
          >
            <ScrollView
              contentContainerStyle={{
                maxWidth: 760,
                width: "100%",
                alignSelf: "center",
              }}
              keyboardShouldPersistTaps="handled"
            >
              <Panel title={editor?.view.label ?? "Record details"}>
                {editor ? (
                  <RecordForm
                    key={`${editor.view.id}:${editor.record?.id ?? "new"}`}
                    view={editor.view}
                    record={editor.record}
                    onSaved={() => setEditor(null)}
                    onCancel={closeOverlay}
                  />
                ) : details ? (
                  <DetailsView
                    view={details.view}
                    record={
                      state.record?.id === details.record.id
                        ? state.record
                        : null
                    }
                  />
                ) : null}
                {details ? (
                  <Button
                    subtle
                    disabled={Boolean(state.pending)}
                    onPress={closeOverlay}
                  >
                    Close details
                  </Button>
                ) : null}
                {state.pending ? (
                  <Notice error>
                    {state.pending.error?.message ??
                      "Saving… Return to the command status on the page after this resolves."}
                  </Notice>
                ) : null}
                {state.pending?.status === "uncertain" ? (
                  <Button onPress={() => void controller.retry()}>
                    Retry original command
                  </Button>
                ) : null}
                {state.pending?.status === "failed" ? (
                  <Button
                    subtle
                    onPress={() => controller.acknowledgeFailure()}
                  >
                    Review values
                  </Button>
                ) : null}
              </Panel>
            </ScrollView>
          </SafeAreaView>
        </Modal>
        <Modal
          visible={leave !== null}
          transparent
          animationType="fade"
          onRequestClose={() => setLeave(null)}
        >
          <SafeAreaView
            style={{
              flex: 1,
              backgroundColor: "#00000066",
              padding: 24,
              justifyContent: "center",
            }}
          >
            <Panel title="Discard unsaved changes?">
              <Body>Your current edit has not been saved.</Body>
              <Row>
                <Button
                  onPress={() => {
                    const action = leave;
                    setLeave(null);
                    controller.setDirty(false);
                    action?.();
                  }}
                >
                  Discard changes
                </Button>
                <Button subtle onPress={() => setLeave(null)}>
                  Keep editing
                </Button>
              </Row>
            </Panel>
          </SafeAreaView>
        </Modal>
      </SafeAreaView>
    </RendererContext.Provider>
  );
}
