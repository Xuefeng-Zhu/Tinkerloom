import { useCallback, useState } from "react";
import { Text, View } from "react-native";
import { Button } from "../components/Button";
import { DraftMediaUploadPanel } from "../media/DraftMediaUploadPanel";
import type { DraftMediaController } from "../media/draft";
import { ensure } from "../runtime/errors";
import type { FullAppController, FullAppState } from "./FullAppController";
import { Card, styles } from "./ui";

function SavedDraftBannerImages({
  controller,
  state,
  media,
}: {
  controller: FullAppController;
  state: FullAppState;
  media: DraftMediaController;
}) {
  const [choice, setChoice] = useState<{
    assetId: string;
    bannerId: string | null;
  } | null>(null);
  const [bannerId, setBannerId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const banners =
    state.candidate?.views.filter((view) => view.type === "banner") ?? [];
  const blocked =
    state.dirty ||
    !!state.editorError ||
    state.busy ||
    state.loading ||
    !!state.pending ||
    state.conflict ||
    state.refreshRequired ||
    !controller.canBuild;
  const receive = useCallback(
    (assetId: string) => {
      const current = controller.getSnapshot();
      ensure(
        controller.draftMedia === media &&
          media.lifetime.active &&
          !current.dirty &&
          !current.editorError &&
          !current.busy &&
          !current.pending &&
          !current.loading &&
          !current.refreshRequired,
        "media_context_changed",
        "The current saved draft changed.",
      );
      setChoice({ assetId, bannerId });
      setError(null);
    },
    [controller, media, bannerId],
  );
  const apply = async () => {
    if (!choice || !bannerId || blocked) return;
    try {
      await controller.applyDraftBannerImage(
        bannerId,
        choice.assetId,
        media.savedContext,
      );
      setChoice(null);
      setError(null);
    } catch {
      setError(
        "The image could not be applied. Check the current saved candidate and choose its banner again.",
      );
    }
  };
  return (
    <Card title="Private banner image">
      <Text style={styles.body}>
        Choose an existing banner, then select a ready private image. Applying
        changes only that banner in your local candidate; Save private candidate
        commits the edit.
      </Text>
      {banners.length ? (
        <View style={styles.row}>
          {banners.map((view) => (
            <Button
              key={view.id}
              label={view.label}
              variant={bannerId === view.id ? "primary" : "secondary"}
              disabled={blocked}
              onPress={() => {
                setBannerId(view.id);
                setChoice(null);
                setError(null);
              }}
            />
          ))}
        </View>
      ) : (
        <Text style={styles.muted}>
          Add and save a banner in the editor before assigning its image.
          Uploading alone never adds a banner.
        </Text>
      )}
      <DraftMediaUploadPanel
        controller={media}
        context={media.savedContext}
        disabled={blocked}
        onReadyOpaqueAssetId={receive}
      />
      {choice ? (
        <Text style={styles.body}>
          A ready private image is selected. Choose Apply to update the selected
          banner.
        </Text>
      ) : null}
      <Button
        label="Apply image to selected banner"
        disabled={
          blocked || !choice || !bannerId || choice.bannerId !== bannerId
        }
        onPress={() => void apply()}
      />
      {blocked ? (
        <Text style={styles.muted}>
          Save or resolve the current edit before selecting or applying an
          image.
        </Text>
      ) : null}
      {error ? (
        <Text accessibilityRole="alert" style={styles.body}>
          {error}
        </Text>
      ) : null}
    </Card>
  );
}
export function DraftBannerImages({
  controller,
  state,
}: {
  controller: FullAppController;
  state: FullAppState;
}) {
  const media = controller.draftMedia;
  if (!media)
    return state.platform?.privateMedia ? (
      <Text style={styles.muted}>
        Private image upload needs an unconsumed saved author draft with current
        builder access and no pending generation or operation.
      </Text>
    ) : null;
  return (
    <SavedDraftBannerImages
      key={JSON.stringify([
        media.savedContext.draftRevision,
        media.savedContext.candidateHash,
      ])}
      controller={controller}
      state={state}
      media={media}
    />
  );
}
