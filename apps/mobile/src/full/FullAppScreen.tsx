import { useCallback, useEffect, useState, useSyncExternalStore } from "react";
import { useFocusEffect } from "expo-router";
import {
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  Text,
  View,
} from "react-native";
import { Button } from "../components/Button";
import { Notice } from "../components/Notice";
import { RuntimeRenderer } from "../renderer/RuntimeRenderer";
import type { FullAppController } from "./FullAppController";
import { fullTemplates } from "./catalog";
import { DeviceAccessPanel } from "./DeviceAccessPanel";
import { GenerationPanel } from "./GenerationPanel";
import { IsolatedPreview } from "./IsolatedPreview";
import { PublicationPanel } from "./PublicationPanel";
import { SpecEditor } from "./SpecEditor";
import { DraftBannerImages } from "./DraftBannerImages";
import { PrivateMediaRecoveryPanel } from "../media/RecoveryPanel";
import type { MediaRuntimeAdapter } from "../media/adapter";
import { Card, Choices, styles } from "./ui";
export interface FullAppScreenProps {
  controller: FullAppController;
  onBack: () => void;
  onShare?: () => void;
  onRuns?: () => void;
  onOpenCreated?: (id: string) => void;
  initialMode?: "live" | "build" | "preview";
}
export function FullAppScreen({
  controller,
  onBack,
  onShare,
  onRuns,
  initialMode,
}: FullAppScreenProps) {
  const state = useSyncExternalStore(
      controller.subscribe,
      controller.getSnapshot,
      controller.getSnapshot,
    ),
    [mode, setMode] = useState<"live" | "build" | "preview">(
      initialMode ?? "live",
    ),
    [leave, setLeave] = useState<(() => void) | null>(null),
    [localError, setLocalError] = useState<string | null>(null);
  useEffect(() => {
    void controller.load();
  }, [controller]);
  useFocusEffect(
    useCallback(
      () => controller.acquireLiveLease(mode === "live"),
      [controller, mode],
    ),
  );
  const navigate = async (action: () => void) => {
    if (state.pending) {
      action();
      return;
    }
    if (mode === "build" && !(await controller.flush())) return;
    const runtime = controller.runtime?.getSnapshot();
    if (runtime?.dirty && !runtime.pending) {
      setLeave(() => action);
      return;
    }
    action();
  };
  const editorVisible =
    !!state.app &&
    !state.app.archived &&
    ["owner", "builder"].includes(state.app.role) &&
    state.app.capabilities.editDefinition === true;
  const locked =
    state.busy || !!state.pending || state.conflict || !controller.canBuild;
  return (
    <KeyboardAvoidingView
      style={styles.screen}
      behavior={Platform.OS === "ios" ? "padding" : undefined}
    >
      <View style={[styles.row, { padding: 12 }]}>
        <Button
          label="Back to workbench"
          variant="quiet"
          onPress={() => {
            void navigate(onBack);
          }}
        />
        <View style={{ flex: 1 }}>
          <Text style={styles.label}>Tinkerloom</Text>
          <Text accessibilityRole="header" style={styles.title}>
            {state.app?.name ?? "Open app"}
          </Text>
        </View>
        {onShare && (
          <Button
            label="Sharing"
            variant="secondary"
            onPress={() => {
              void navigate(onShare);
            }}
          />
        )}
        {onRuns &&
          state.app &&
          ["owner", "builder"].includes(state.app.role) && (
            <Button
              label="Reminder runs"
              variant="quiet"
              onPress={() => {
                void navigate(onRuns);
              }}
            />
          )}
        <Button
          label="Refresh access"
          variant="quiet"
          disabled={state.loading || state.busy}
          onPress={() => {
            void controller.load();
          }}
        />
      </View>
      {leave && (
        <Card title="Unsaved record edits">
          <Text style={styles.body}>
            Leaving this screen discards the record form’s unsaved local edits.
            No saved operation is removed.
          </Text>
          <View style={styles.row}>
            <Button label="Keep editing" onPress={() => setLeave(null)} />
            <Button
              label="Discard unsaved form edits"
              variant="secondary"
              onPress={() => {
                controller.runtime?.setDirty(false);
                const action = leave;
                setLeave(null);
                action();
              }}
            />
          </View>
        </Card>
      )}
      {(state.error || localError) && (
        <Notice text={localError ?? state.error!} error />
      )}
      {state.editorError && <Notice text={state.editorError} error />}
      {state.pending && (
        <Card title="Retained operation">
          <Text style={styles.body}>
            {state.pendingStatus === "sending"
              ? "Saving…"
              : state.pendingStatus === "uncertain"
                ? "The result is still unconfirmed."
                : "The server rejected this change."}
          </Text>
          <Text style={styles.muted}>
            Your original change and approvals are saved for recovery. Leaving
            or refreshing does not undo it. Check its outcome before making
            another change.
          </Text>
          <View style={styles.row}>
            {state.pendingStatus === "uncertain" && (
              <Button
                label="Check original outcome"
                disabled={state.busy}
                onPress={() => {
                  void controller.retry();
                }}
              />
            )}
            {state.pendingStatus === "rejected" && (
              <Button
                label="Acknowledge definitive rejection"
                variant="secondary"
                disabled={state.busy}
                onPress={() => {
                  void controller.acknowledgeRejection();
                }}
              />
            )}
          </View>
        </Card>
      )}
      {state.app && (
        <View style={{ padding: 12 }}>
          <Choices
            label="App mode"
            disabled={state.busy}
            values={
              editorVisible
                ? (["live", "build", "preview"] as const)
                : (["live"] as const)
            }
            value={editorVisible ? mode : "live"}
            onChange={(next) => {
              void navigate(() => {
                setLocalError(null);
                setMode(next);
              });
            }}
          />
        </View>
      )}
      {state.loading && !state.app && (
        <Notice text="Loading the current app and access…" />
      )}
      {mode === "live" || !editorVisible ? (
        <View style={{ flex: 1 }}>
          {state.runtimeOutdated && (
            <Card title="A newer version is available">
              <Text style={styles.body}>
                The current form or retained record command stays bound to its
                original version. Resolve it before opening the latest version.
              </Text>
              <Button
                label="Open latest version"
                onPress={() => {
                  void controller.useLatestVersion();
                }}
              />
            </Card>
          )}
          {state.app?.archived && (
            <Notice text="Archived app · Existing authorized reads and exact receipt checks remain available. New record writes are disabled." />
          )}
          {(controller.runtime?.adapter as MediaRuntimeAdapter | undefined)
            ?.media ? (
            <ScrollView style={{ maxHeight: 220 }}>
              <PrivateMediaRecoveryPanel
                controller={
                  (controller.runtime!.adapter as MediaRuntimeAdapter).media!
                }
              />
            </ScrollView>
          ) : null}
          {controller.runtime ? (
            <RuntimeRenderer
              controller={controller.runtime}
              timers={controller.timers ?? undefined}
              device={controller.device ?? undefined}
            />
          ) : (
            state.app && (
              <Notice text="This app has no published version yet. Open Build to create a private candidate." />
            )
          )}
          {controller.device && (
            <ScrollView style={{ maxHeight: 300 }}>
              <DeviceAccessPanel device={controller.device} />
            </ScrollView>
          )}
        </View>
      ) : mode === "preview" ? (
        !state.candidate && (
          <Notice text="Create a private candidate in Build to try an isolated preview." />
        )
      ) : (
        <ScrollView
          keyboardShouldPersistTaps="handled"
          contentContainerStyle={styles.content}
        >
          <Text accessibilityRole="header" style={styles.heading}>
            Your private workbench
          </Text>
          <Text style={styles.body}>
            Only your current author draft appears here. Saved candidates stay
            private until you publish a reviewed version.
          </Text>
          <GenerationPanel controller={controller} state={state} />
          {!state.candidate && (
            <Card title="Or choose a starter">
              <Text style={styles.muted}>
                Choosing a starter creates a private candidate. It does not copy
                preview records or publish.
              </Text>
              {fullTemplates.map((template) => (
                <Button
                  key={template.id}
                  label={`${template.spec.name} · ${template.caption}`}
                  variant="secondary"
                  disabled={locked}
                  onPress={() => {
                    try {
                      controller.setCandidate(template.spec);
                      void controller.save();
                    } catch (error) {
                      setLocalError(
                        error instanceof Error
                          ? error.message
                          : "Could not choose the starter.",
                      );
                    }
                  }}
                />
              ))}
            </Card>
          )}
          {state.candidate && (
            <>
              <View style={styles.row}>
                <Button
                  label={
                    state.dirty ? "Save private candidate" : "Candidate saved"
                  }
                  disabled={locked || !state.dirty}
                  onPress={() => {
                    void controller.save();
                  }}
                />
                <Button
                  label="Discard unsaved local edits"
                  variant="secondary"
                  disabled={
                    state.busy ||
                    !!state.pending ||
                    (!state.dirty && !state.conflict && !state.editorError)
                  }
                  onPress={() => controller.discardLocalEdits()}
                />
                <Text accessibilityLiveRegion="polite" style={styles.muted}>
                  {state.busy
                    ? "Saving…"
                    : state.editorError
                      ? "Fix the invalid local edit"
                      : state.conflict
                        ? "The server draft changed; reload before continuing."
                        : state.dirty
                          ? "Unsaved local changes"
                          : "Private candidate is saved"}
                </Text>
              </View>
              <DraftBannerImages controller={controller} state={state} />
              {state.previewImagesLoading ? (
                <Notice text="Loading approved private banner images for the isolated preview…" />
              ) : null}
              {state.previewUnavailableAssetCount ? (
                <Notice text="Some private banner images are unavailable. The isolated preview keeps placeholders; no image upload or record write runs there." />
              ) : null}
              <SpecEditor
                staticImageAssets={state.previewStaticImageAssets}
                spec={state.candidate}
                disabled={locked}
                onEdit={(edit, debounce) => {
                  controller.edit(edit, debounce);
                  if (!debounce) void controller.save();
                }}
                onReplace={(input) => {
                  controller.setCandidate(input);
                  void controller.save();
                }}
              />
              <PublicationPanel
                key={state.app?.draft?.candidateHash ?? "local"}
                controller={controller}
                state={state}
              />
            </>
          )}
        </ScrollView>
      )}
      {editorVisible && state.candidate && (
        <View
          style={{ flex: 1, display: mode === "preview" ? "flex" : "none" }}
          accessibilityElementsHidden={mode !== "preview"}
          importantForAccessibility={
            mode === "preview" ? "auto" : "no-hide-descendants"
          }
        >
          <IsolatedPreview
            staticImageAssets={state.previewStaticImageAssets}
            spec={state.candidate}
            onExit={() => setMode("build")}
          />
        </View>
      )}
    </KeyboardAvoidingView>
  );
}
