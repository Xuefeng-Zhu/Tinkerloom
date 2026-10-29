import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { Pressable, Text, View } from "react-native";
import { canonicalJson } from "../spec/schema";
import type { PrivateMediaController } from "./controller";
import type { MediaUploadContext } from "./types";
import { attachReadyMedia } from "./attachment";

/** Import this module directly; the pure media index deliberately has no UI imports. */
export function PrivateMediaRecoveryPanel({
  controller,
  destination,
  onAttach,
  disabled: externallyDisabled = false,
}: {
  controller: PrivateMediaController;
  destination?: MediaUploadContext;
  onAttach?: (assetId: string) => void;
  disabled?: boolean;
}) {
  const state = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
    controller.getSnapshot,
  );
  const [feedback, setFeedback] = useState<{
    controller: PrivateMediaController;
    identity: string;
    message: string | null;
  } | null>(null);
  const lifetime = useRef<{ active: boolean } | null>(null);
  const identity = canonicalJson(destination ?? null);
  const message =
    feedback?.controller === controller && feedback.identity === identity
      ? feedback.message
      : null;
  const setMessage = (message: string | null) =>
    setFeedback({ controller, identity, message });
  useEffect(() => {
    const current = { active: true };
    lifetime.current = current;
    return () => {
      current.active = false;
    };
  }, [controller, identity, externallyDisabled, onAttach]);
  if (destination && canonicalJson(controller.currentContext()) !== identity)
    return null;
  if (!state.initialized && !state.error) return null;
  if (!state.stage && !state.error) return null;
  const run = async (kind: "retry" | "poll" | "discard" | "attach") => {
    const current = lifetime.current;
    if (!current?.active || externallyDisabled) return;
    setMessage(null);
    try {
      if (kind === "discard") {
        await controller.discard();
        if (current.active)
          setMessage(
            "Local image recovery discarded. This does not delete a server image or save the form.",
          );
      } else if (kind === "attach" && destination && onAttach) {
        const attached = await attachReadyMedia(
          controller,
          destination,
          () => current.active,
          onAttach,
        );
        if (current.active)
          setMessage(
            attached
              ? "Image attached to this field. Save the form to keep it."
              : "The image is still processing. Check again later.",
          );
      } else {
        const ready =
          kind === "retry" ? await controller.retry() : await controller.poll();
        if (current.active)
          setMessage(
            ready
              ? "The private image is ready. Attach it to the matching field before saving."
              : "The image is still processing. Check again later.",
          );
      }
    } catch {
      if (current.active)
        setMessage(
          "The image request is unavailable. Check retained status before trying again.",
        );
    }
  };
  const disabled = externallyDisabled || state.busy || state.accessDenied;
  const button = (
    label: string,
    kind: "retry" | "poll" | "discard" | "attach",
  ) => (
    <Pressable
      key={kind}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled }}
      disabled={disabled}
      onPress={() => void run(kind)}
      style={{
        paddingVertical: 10,
        paddingHorizontal: 12,
        borderWidth: 1,
        borderColor: "#64746a",
        borderRadius: 8,
        opacity: disabled ? 0.5 : 1,
      }}
    >
      <Text>{label}</Text>
    </Pressable>
  );
  return (
    <View
      accessibilityLabel="Private image recovery"
      style={{
        gap: 8,
        padding: 12,
        borderWidth: 1,
        borderColor: "#64746a",
        borderRadius: 10,
      }}
    >
      <Text style={{ fontWeight: "600" }}>Private image recovery</Text>
      <Text>
        {state.uncertain
          ? "An image request is unconfirmed. Retry sends the retained request with the same identity."
          : state.stage === "ready"
            ? "The private image is ready. Uploading does not save a record."
            : "An image upload is retained locally. Processing may finish later; checking status does not repeat upload writes."}
      </Text>
      <Text>
        {Math.min(state.uploadedBytes, state.inputBytes).toLocaleString()} of{" "}
        {state.inputBytes.toLocaleString()} bytes uploaded
      </Text>
      {state.error || message ? (
        <Text accessibilityRole="alert">{message ?? state.error}</Text>
      ) : null}
      <View style={{ flexDirection: "row", gap: 8, flexWrap: "wrap" }}>
        {state.pending && state.stage !== "failed"
          ? button("Retry retained upload", "retry")
          : null}
        {state.stage === "chunks" && !state.pending
          ? button("Resume retained upload", "retry")
          : null}
        {["processing", "ready"].includes(state.stage ?? "")
          ? button("Check image status", "poll")
          : null}
        {state.stage === "ready" &&
        destination &&
        onAttach &&
        canonicalJson(controller.currentContext()) === identity
          ? button("Attach ready image", "attach")
          : null}
        {button("Discard local recovery", "discard")}
      </View>
    </View>
  );
}
