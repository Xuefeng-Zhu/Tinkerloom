import { useEffect, useState, useSyncExternalStore } from "react";
import { View } from "react-native";
import type { PreviewStaticImageAssets } from "../runtime/previewImageAssets";
import type { AppSpec } from "../spec/types";
import { RuntimeRenderer } from "../renderer/RuntimeRenderer";
import { Notice } from "../components/Notice";
import { PreviewSession } from "./PreviewSession";
/** No transport, host storage, device bridge or live records can enter this component. */
export function IsolatedPreview({
  spec,
  staticImageAssets,
  onExit,
}: {
  spec: AppSpec;
  staticImageAssets?: PreviewStaticImageAssets;
  onExit?: () => void;
}) {
  const [preview] = useState(
    () => new PreviewSession(spec, "try", staticImageAssets),
  );
  const state = useSyncExternalStore(
    preview.subscribe,
    preview.getSnapshot,
    preview.getSnapshot,
  );
  useEffect(() => {
    preview.update(spec, staticImageAssets);
  }, [preview, spec, staticImageAssets]);
  useEffect(() => () => preview.dispose(), [preview]);
  return (
    <View style={{ flex: 1, minHeight: 400 }}>
      <Notice text="Isolated preview · Synthetic records. Approved banner images may appear. Changes here never become live records or device commands." />
      {state.restarted && (
        <Notice text="A structural change started a fresh sample session. Presentation changes preserve the sample session." />
      )}
      <RuntimeRenderer
        controller={state.session.controller}
        timers={state.session.timers}
        onExit={onExit}
      />
    </View>
  );
}
