import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import { useFocusEffect, useIsFocused, usePreventRemove } from "expo-router";
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  Text,
  View,
} from "react-native";
import { Button } from "../components/Button";
import { Notice } from "../components/Notice";
import { RuntimeRenderer } from "../renderer/RuntimeRenderer";
import type { FullAppController } from "./FullAppController";
import { requestedDeviceCapabilities } from "../spec/bindings";
import { fullTemplates } from "./catalog";
import { DeviceAccessPanel } from "./DeviceAccessPanel";
import { GenerationPanel } from "./GenerationPanel";
import { IsolatedPreview } from "./IsolatedPreview";
import { PublicationPanel } from "./PublicationPanel";
import { SpecEditor } from "./SpecEditor";
import { DraftBannerImages } from "./DraftBannerImages";
import { mediaRecoveryPresentation } from "../media/controller";
import { PrivateMediaRecoveryPanel } from "../media/RecoveryPanel";
import type { MediaRuntimeAdapter } from "../media/adapter";
import { Card, styles } from "./ui";
import type { RuntimeLocation } from "../runtime/types";
import {
  NavigationEpoch,
  guardHostNavigation,
  fullRouteParams,
  parseFullRoute,
} from "./navigation";
import type {
  FullMode,
  FullRouteRequest,
  DeferredRouteAttempt,
} from "./navigation";
const noMediaSnapshot = () => null;
const noMediaSubscription = () => () => {};
export interface FullAppScreenProps {
  controller: FullAppController;
  onBack: () => void;
  onShare?: () => void;
  onRuns?: () => void;
  onOpenCreated?: (id: string) => void;
  initialMode?: "live" | "build" | "preview";
  route?: FullRouteRequest;
  protectedLocationOwned?: boolean;
  onProtectionChange?: (locked: boolean) => void;
  onRestoreProtectedLocation?: (
    request: FullRouteRequest,
  ) => "current" | "restored" | "unavailable";
  externalAttempt?: DeferredRouteAttempt;
  onDismissExternalAttempt?: (id: number) => void;
  onLocationChange?: (
    location: RuntimeLocation,
    kind: "push" | "pop" | "replace",
    mode: FullMode,
  ) => void;
}
export function FullAppScreen({
  controller,
  onBack,
  onShare,
  onRuns,
  initialMode,
  route,
  protectedLocationOwned = true,
  onProtectionChange,
  onRestoreProtectedLocation,
  externalAttempt,
  onDismissExternalAttempt,
  onLocationChange,
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
  const focused = useIsFocused();
  const [epoch] = useState(() => new NavigationEpoch());
  const focusedRef = useRef(focused);
  useLayoutEffect(() => {
    focusedRef.current = focused;
  }, [focused]);
  const runtimeController = controller.runtime;
  const runtimeState = useSyncExternalStore(
    runtimeController?.subscribe ?? noMediaSubscription,
    runtimeController?.getSnapshot ?? noMediaSnapshot,
    runtimeController?.getSnapshot ?? noMediaSnapshot,
  );
  useLayoutEffect(() => {
    const observe = () => {
      if (focusedRef.current && controller.host.lifetime.active)
        onProtectionChange?.(!controller.canLeave);
    };
    observe();
    const host = controller.subscribe(observe);
    const runtime = runtimeController?.subscribe(observe);
    return () => {
      host();
      runtime?.();
    };
  }, [controller, runtimeController, onProtectionChange]);
  const handledRoute = useRef<string | null>(null);
  const routeCallback = useRef(onLocationChange);
  useLayoutEffect(() => {
    routeCallback.current = onLocationChange;
  }, [onLocationChange]);
  const modeRef = useRef(mode);
  useLayoutEffect(() => {
    modeRef.current = mode;
  }, [mode]);
  const media = (controller.runtime?.adapter as MediaRuntimeAdapter | undefined)
    ?.media;
  const mediaState = useSyncExternalStore(
    media?.subscribe ?? noMediaSubscription,
    media?.getSnapshot ?? noMediaSnapshot,
    media?.getSnapshot ?? noMediaSnapshot,
  );
  const showMediaRecovery =
    mediaState && mediaRecoveryPresentation(mediaState) !== "hidden";
  useEffect(() => {
    if (!controller.getSnapshot().app) void controller.load();
  }, [controller]);
  useEffect(() => {
    if (!focused) {
      epoch.cancel();
      handledRoute.current = null;
    }
    return () => epoch.cancel();
  }, [controller, epoch, focused]);
  useFocusEffect(
    useCallback(
      () => controller.acquireLiveLease(mode === "live"),
      [controller, mode],
    ),
  );
  const removalHandler = useRef<((repeat: () => void) => void) | null>(null);
  const disablePrevention = usePreventRemove(
    focused &&
      protectedLocationOwned &&
      (!controller.canLeave ||
        !!runtimeState?.pending ||
        !!runtimeState?.dirty),
    ({ repeat }) => {
      removalHandler.current?.(repeat);
    },
  );
  const navigate = useCallback(
    (action: () => void, keepExternalAttempt = false) => {
      if (!keepExternalAttempt && externalAttempt)
        onDismissExternalAttempt?.(externalAttempt.id);
      return guardHostNavigation({
        source: controller,
        epoch,
        focused: () => focusedRef.current,
        action,
        prompt: (accept) => setLeave(() => accept),
        blocked: () =>
          setLocalError(
            "Resolve the retained operation before leaving this location.",
          ),
        beforeNavigate: disablePrevention,
      });
    },
    [
      controller,
      epoch,
      disablePrevention,
      externalAttempt,
      onDismissExternalAttempt,
    ],
  );
  useLayoutEffect(() => {
    removalHandler.current = (repeat) => {
      void navigate(repeat);
    };
  }, [navigate]);
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      await Promise.resolve();
      if (cancelled) return;
      const requested = externalAttempt?.route ?? route;
      if (!focused || !requested) return;
      const requestKey = `${runtimeController?.scopeId ?? "unpublished"}:${externalAttempt ? `attempt:${externalAttempt.id}` : requested.key}`;
      if (handledRoute.current === requestKey) return;
      handledRoute.current = requestKey;
      if (!protectedLocationOwned) {
        // Forward/PUSH can retain the source route, so no remove event fires.
        // Return to that exact component before asking about its local input.
        disablePrevention();
        const restored = onRestoreProtectedLocation?.(requested);
        if (restored !== "restored")
          setLocalError(
            "The original unsaved form is unavailable in this navigation stack. Its retained operation has not been removed.",
          );
        return;
      }
      if (!runtimeController) {
        if (!controller.getSnapshot().app) {
          handledRoute.current = null;
          return;
        }
        const emptyLocation = { pageId: "__legacy__" };
        const currentMode = modeRef.current;
        if (
          requested.location.recordId ||
          requested.location.pageId ||
          requested.location.editing
        ) {
          setLocalError(
            "This app has no published version for that page or record.",
          );
          handledRoute.current = `unpublished:${parseFullRoute(fullRouteParams(controller.host.lifetime.scope.appId, emptyLocation, currentMode)).key}`;
          routeCallback.current?.(emptyLocation, "replace", currentMode);
          if (externalAttempt) onDismissExternalAttempt?.(externalAttempt.id);
          return;
        }
        if (!externalAttempt && requested.mode === currentMode) return;
        handledRoute.current = `unpublished:${parseFullRoute(fullRouteParams(controller.host.lifetime.scope.appId, emptyLocation, currentMode)).key}`;
        routeCallback.current?.(emptyLocation, "replace", currentMode);
        void navigate(() => {
          const nextMode = controller.canBuild ? requested.mode : "live";
          setMode(nextMode);
          if (externalAttempt) {
            handledRoute.current = `unpublished:${route?.key ?? requested.key}`;
            routeCallback.current?.(emptyLocation, "push", nextMode);
            onDismissExternalAttempt?.(externalAttempt.id);
          } else {
            handledRoute.current = `unpublished:${parseFullRoute(fullRouteParams(controller.host.lifetime.scope.appId, emptyLocation, nextMode)).key}`;
            routeCallback.current?.(emptyLocation, "replace", nextMode);
          }
        }, true);
        return;
      }
      const canonical = parseFullRoute(
        fullRouteParams(
          controller.host.lifetime.scope.appId,
          runtimeController.getSnapshot().location,
          modeRef.current,
        ),
      );
      if (
        !externalAttempt &&
        !requested.error &&
        requested.key === canonical.key &&
        !controller.canLeave
      )
        return;
      const valid = epoch.next();
      const active = () =>
        valid() &&
        focusedRef.current &&
        controller.host.lifetime.active &&
        controller.runtime === runtimeController;
      const replaceLocation = (
        location: RuntimeLocation,
        nextMode: FullMode,
      ) => {
        handledRoute.current = `${runtimeController.scopeId}:${
          parseFullRoute(
            fullRouteParams(
              controller.host.lifetime.scope.appId,
              location,
              nextMode,
            ),
          ).key
        }`;
        routeCallback.current?.(location, "replace", nextMode);
      };
      const restore = () => {
        if (active())
          replaceLocation(
            runtimeController.getSnapshot().location,
            modeRef.current,
          );
      };
      if (requested.error) {
        setLocalError(requested.error);
        restore();
        return;
      }
      const apply = async () => {
        if (!active()) return;
        try {
          // A link is never authority: refresh the manifest before its authorized record lookup.
          await controller.load();
          if (!active()) return;
          const authorized = controller.getSnapshot();
          if (!authorized.app || authorized.error)
            throw new Error(
              authorized.error ??
                "This app is unavailable with your current access.",
            );
          if (
            authorized.pending ||
            authorized.busy ||
            runtimeController.getSnapshot().pending
          ) {
            setLocalError(
              "Resolve the retained operation before opening this app link.",
            );
            restore();
            return;
          }
          const result = await runtimeController.applyLocation(
            requested.location,
          );
          if (!active()) return;
          if (result !== "applied") {
            restore();
            if (result === "blocked")
              setLocalError(
                "Resolve the retained operation before opening this app link.",
              );
            return;
          }
          const app = controller.getSnapshot().app;
          const nextMode =
            app &&
            !app.archived &&
            ["owner", "builder"].includes(app.role) &&
            app.capabilities.editDefinition === true
              ? requested.mode
              : "live";
          setMode(nextMode);
          setLocalError(null);
          if (externalAttempt) {
            // The source instance is now clean. Resume the explicit visit as a supported push.
            handledRoute.current = `${runtimeController.scopeId}:${route?.key ?? requested.key}`;
            routeCallback.current?.(
              runtimeController.getSnapshot().location,
              "push",
              nextMode,
            );
            onDismissExternalAttempt?.(externalAttempt.id);
          } else
            replaceLocation(runtimeController.getSnapshot().location, nextMode);
        } catch (error) {
          if (!active()) return;
          setLocalError(
            error instanceof Error
              ? error.message
              : "This record is unavailable with your current access.",
          );
          restore();
        }
      };
      const current = controller.getSnapshot();
      const snapshot = runtimeController.getSnapshot();
      if (current.pending || current.busy || snapshot.pending) {
        setLocalError(
          "Resolve the retained operation before opening this app link.",
        );
        restore();
      } else if (snapshot.dirty || current.dirty || current.editorError) {
        restore();
        // Save the private candidate before changing mode; only record form input needs discard consent.
        if (
          (current.dirty || current.editorError) &&
          !(await controller.flush())
        )
          return;
        if (!active()) return;
        if (
          controller.getSnapshot().pending ||
          controller.getSnapshot().busy ||
          runtimeController.getSnapshot().pending
        )
          return;
        if (runtimeController.getSnapshot().dirty)
          setLeave(() => () => {
            if (active()) void apply();
          });
        else void apply();
      } else void apply();
    })();
    return () => {
      cancelled = true;
    };
  }, [
    controller,
    epoch,
    focused,
    route,
    runtimeController,
    protectedLocationOwned,
    onRestoreProtectedLocation,
    externalAttempt,
    onDismissExternalAttempt,
    disablePrevention,
    navigate,
    state.app?.id,
  ]);
  const locationChanged = (
    location: RuntimeLocation,
    kind: "push" | "pop" | "replace",
  ) => {
    if (!focusedRef.current || !controller.host.lifetime.active) return;
    epoch.cancel();
    setLeave(null);
    setLocalError(null);
    if (externalAttempt) onDismissExternalAttempt?.(externalAttempt.id);
    if (controller.canLeave) disablePrevention();
    onLocationChange?.(location, kind, modeRef.current);
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
            <Button
              label="Keep editing"
              onPress={() => {
                epoch.cancel();
                setLeave(null);
                if (externalAttempt)
                  onDismissExternalAttempt?.(externalAttempt.id);
              }}
            />
            <Button
              label="Discard unsaved form edits"
              variant="secondary"
              onPress={() => {
                if (
                  !focusedRef.current ||
                  !controller.host.lifetime.active ||
                  controller.getSnapshot().pending ||
                  controller.getSnapshot().busy ||
                  controller.runtime?.getSnapshot().pending
                )
                  return;
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
          <View style={{ gap: 8 }}>
            <Text style={styles.muted}>App mode</Text>
            <View
              accessibilityRole="radiogroup"
              accessibilityLabel="App mode"
              style={styles.row}
            >
              {(editorVisible
                ? (["live", "build", "preview"] as const)
                : (["live"] as const)
              ).map((next) => {
                const checked = next === (editorVisible ? mode : "live");
                return (
                  <Pressable
                    key={next}
                    accessibilityRole="radio"
                    accessibilityLabel={`App mode: ${next}`}
                    accessibilityState={{ checked, disabled: state.busy }}
                    aria-checked={checked}
                    aria-disabled={state.busy}
                    disabled={state.busy}
                    onPress={() => {
                      void navigate(() => {
                        setLocalError(null);
                        setMode(next);
                        if (controller.runtime)
                          onLocationChange?.(
                            controller.runtime.getSnapshot().location,
                            "push",
                            next,
                          );
                      });
                    }}
                    style={[
                      styles.choice,
                      checked && styles.chosen,
                      state.busy && { opacity: 0.5 },
                    ]}
                  >
                    <Text style={styles.body}>{next}</Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        </View>
      )}
      {state.loading && !state.app && (
        <Notice text="Loading the current app and access…" />
      )}
      {!protectedLocationOwned ? (
        <Card title="Unsaved form kept in its original app visit">
          <Text style={styles.body}>
            Returning to the original form. This new visit cannot replace its
            local input.
          </Text>
          {runtimeState?.pending ? (
            <>
              <Text style={styles.body}>
                The original record operation remains retained:{" "}
                {runtimeState.pending.status}.
              </Text>
              {runtimeState.pending.status === "uncertain" ? (
                <Button
                  label="Check original record outcome"
                  onPress={() => {
                    void runtimeController?.retry();
                  }}
                />
              ) : null}
              {runtimeState.pending.status === "failed" ? (
                <Button
                  label="Acknowledge definitive record rejection"
                  onPress={() => runtimeController?.acknowledgeFailure()}
                />
              ) : null}
            </>
          ) : null}
        </Card>
      ) : null}
      {!protectedLocationOwned ? null : mode === "live" || !editorVisible ? (
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
          {media && showMediaRecovery ? (
            <ScrollView style={{ maxHeight: 220 }}>
              <PrivateMediaRecoveryPanel controller={media} />
            </ScrollView>
          ) : null}
          {controller.runtime ? (
            <RuntimeRenderer
              controller={controller.runtime}
              timers={controller.timers ?? undefined}
              device={controller.device ?? undefined}
              onExit={() => {
                void navigate(onBack);
              }}
              onLocationChange={locationChanged}
            />
          ) : (
            state.app && (
              <Notice text="This app has no published version yet. Open Build to create a private candidate." />
            )
          )}
          {controller.device &&
            controller.runtime &&
            requestedDeviceCapabilities(controller.runtime.adapter.spec)
              .length > 0 && (
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
                onFlush={async () =>
                  controller.canBuild &&
                  (await controller.flush()) &&
                  controller.canBuild
                }
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
      {protectedLocationOwned && editorVisible && state.candidate && (
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
            onExit={() => {
              void navigate(() => {
                setMode("build");
                if (controller.runtime)
                  onLocationChange?.(
                    controller.runtime.getSnapshot().location,
                    "push",
                    "build",
                  );
              });
            }}
          />
        </View>
      )}
    </KeyboardAvoidingView>
  );
}
