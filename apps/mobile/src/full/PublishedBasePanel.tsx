import { Text } from "react-native";
import { Button } from "../components/Button";
import type { FullAppController, FullAppState } from "./FullAppController";
import { Card, styles } from "./ui";
/** Read-only presentation; only the explicit button invokes the guarded copy/save. */
export function PublishedBasePanel({
  controller,
  state,
}: {
  controller: FullAppController;
  state: FullAppState;
}) {
  const version = state.app?.version;
  if (!version || state.candidate || state.app?.draft || !controller.canBuild)
    return null;
  return (
    <Card title="Customize your published app">
      <Text style={styles.body}>
        The isolated preview shows published version {version.number} with
        synthetic records. Edit published version saves its current fields,
        pages, actions and approved image references as your private draft.
        Review and publish separately when ready.
      </Text>
      <Button
        label="Edit published version"
        disabled={!controller.canEditPublishedVersion}
        onPress={() => {
          void controller.editPublishedVersion();
        }}
      />
    </Card>
  );
}
