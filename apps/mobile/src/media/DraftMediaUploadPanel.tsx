import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { Image, Pressable, Text, View } from "react-native";
import type { DraftMediaController, SavedDraftMediaContext } from "./draft";
import { selectReadyDraftMedia } from "./draft";
import { PrivateMediaRecoveryPanel } from "./RecoveryPanel";

function DraftImagePreview({
  controller,
  assetId,
}: {
  controller: DraftMediaController;
  assetId: string;
}) {
  const [result, setResult] = useState<{
    controller: DraftMediaController;
    assetId: string;
    uri: string;
  } | null>(null);
  useEffect(() => {
    let active = true;
    controller.read(assetId, "thumbnail").then(
      (image) => {
        if (active && controller.lifetime.active)
          setResult({ controller, assetId, uri: image.uri });
      },
      () => {},
    );
    return () => {
      active = false;
    };
  }, [controller, assetId]);
  return result?.controller === controller &&
    result.assetId === assetId &&
    controller.lifetime.active ? (
    <Image
      source={{ uri: result.uri }}
      accessibilityLabel="Ready private draft image"
      accessible
      resizeMode="contain"
      style={{ width: "100%", height: 160 }}
    />
  ) : (
    <Text>Private preview is loading or unavailable.</Text>
  );
}

/** Selecting an opaque ready ID never saves a draft, inserts a static reference or publishes. */
export function DraftMediaUploadPanel({
  controller,
  context,
  onReadyOpaqueAssetId,
  disabled: externallyDisabled = false,
}: {
  controller: DraftMediaController;
  context: SavedDraftMediaContext;
  onReadyOpaqueAssetId: (assetId: string) => void;
  disabled?: boolean;
}) {
  const state = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
    controller.getSnapshot,
  );
  const [feedback, setFeedback] = useState<{
    controller: DraftMediaController;
    revision: number;
    hash: string;
    message: string;
  } | null>(null);
  const active = useRef<{ current: boolean } | null>(null);
  const revision = context.draftRevision,
    candidate = context.candidateHash;
  useEffect(() => {
    const current = { current: true };
    active.current = current;
    return () => {
      current.current = false;
    };
  }, [
    controller,
    revision,
    candidate,
    onReadyOpaqueAssetId,
    externallyDisabled,
  ]);
  const matches =
    controller.savedContext.draftRevision === revision &&
    controller.savedContext.candidateHash === candidate;
  const disabled =
    externallyDisabled ||
    !matches ||
    !controller.lifetime.active ||
    !state.initialized ||
    state.busy ||
    state.accessDenied;
  const message =
    feedback?.controller === controller &&
    feedback.revision === revision &&
    feedback.hash === candidate
      ? feedback.message
      : null;
  const report = (message: string) =>
    setFeedback({ controller, revision, hash: candidate, message });
  const pick = async () => {
    const scope = active.current;
    if (!scope?.current || disabled) return;
    let picked: Awaited<ReturnType<DraftMediaController["pickImage"]>> = null;
    try {
      picked = await controller.pickImage();
      if (!scope.current || !picked) return;
      await controller.uploadDraft(picked);
      if (scope.current)
        report(
          "Image ready. Choose Use this private image to return its ID; the draft remains unchanged.",
        );
    } catch {
      if (scope.current)
        report(
          "The image is not ready or the saved draft changed. Use retained recovery below; no draft was saved.",
        );
    } finally {
      picked?.bytes.fill(0);
    }
  };
  const select = async () => {
    const scope = active.current;
    if (!scope?.current || disabled) return;
    try {
      const selected = await selectReadyDraftMedia(
        controller,
        { draftRevision: revision, candidateHash: candidate },
        () => scope.current,
        onReadyOpaqueAssetId,
      );
      if (scope.current)
        report(
          selected
            ? "Ready image ID selected. Review the explicit editor change before saving or publishing."
            : "The private image is still processing.",
        );
    } catch {
      if (scope.current)
        report(
          "The image cannot be selected for this saved draft. Its revision, access or generation state may have changed.",
        );
    }
  };
  return (
    <View
      accessibilityLabel="Saved draft private image upload"
      style={{
        gap: 10,
        padding: 12,
        borderWidth: 1,
        borderColor: "#64746a",
        borderRadius: 10,
      }}
    >
      <Text style={{ fontWeight: "600" }}>Private draft image</Text>
      <Text>
        Upload against this saved draft. Selecting a ready image returns an
        opaque ID; it does not save, publish or add a banner automatically.
      </Text>
      {!matches || !controller.lifetime.active ? (
        <Text>
          Reopen image upload from the current saved draft before continuing.
        </Text>
      ) : null}
      {message ? <Text accessibilityRole="alert">{message}</Text> : null}
      <Pressable
        accessibilityRole="button"
        accessibilityState={{ disabled }}
        disabled={disabled}
        onPress={() => void pick()}
        style={{
          padding: 12,
          opacity: disabled ? 0.5 : 1,
          borderWidth: 1,
          borderColor: "#64746a",
          borderRadius: 8,
        }}
      >
        <Text>Choose private image</Text>
      </Pressable>
      {state.asset?.status === "ready" &&
      matches &&
      controller.lifetime.active ? (
        <>
          <DraftImagePreview
            controller={controller}
            assetId={state.asset.assetId}
          />
          <Pressable
            accessibilityRole="button"
            accessibilityState={{ disabled }}
            disabled={disabled}
            onPress={() => void select()}
            style={{
              padding: 12,
              opacity: disabled ? 0.5 : 1,
              borderWidth: 1,
              borderColor: "#64746a",
              borderRadius: 8,
            }}
          >
            <Text>Use this private image</Text>
          </Pressable>
        </>
      ) : null}
      {matches && controller.lifetime.active ? (
        <PrivateMediaRecoveryPanel
          controller={controller}
          destination={{ draftRevision: revision }}
          disabled={externallyDisabled}
        />
      ) : null}
    </View>
  );
}
