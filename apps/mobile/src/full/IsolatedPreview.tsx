import { useEffect, useState, useSyncExternalStore } from "react";
import { View } from "react-native";
import type { AppSpec } from "../spec/types";
import { RuntimeRenderer } from "../renderer/RuntimeRenderer";
import { Notice } from "../components/Notice";
import { PreviewSession } from "./PreviewSession";
/** No transport, host storage, device bridge or live records can enter this component. */
export function IsolatedPreview({
  spec,
  onExit,
}: {
  spec: AppSpec;
  onExit?: () => void;
}) {
  const [preview] = useState(() => new PreviewSession(spec));
  const state = useSyncExternalStore(
    preview.subscribe,
    preview.getSnapshot,
    preview.getSnapshot,
  );
  useEffect(() => {
    preview.update(spec);
  }, [preview, spec]);
  useEffect(() => () => preview.dispose(), [preview]);
  return (
    <View style={{ flex: 1, minHeight: 400 }}>
      <Notice text="Isolated preview · Synthetic sample records. Changes here never become live records or device commands." />
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
