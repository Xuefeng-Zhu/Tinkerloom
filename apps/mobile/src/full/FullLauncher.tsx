import { useEffect, useState, useSyncExternalStore } from "react";
import {
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  Text,
  View,
} from "react-native";
import { Button } from "../components/Button";
import { Field } from "../components/Field";
import { Notice } from "../components/Notice";
import type { FullWorkspaceController } from "./FullWorkspaceController";
import { fullTemplates } from "./catalog";
import { IsolatedPreview } from "./IsolatedPreview";
import { Card, Toggle, styles } from "./ui";
export interface FullLauncherProps {
  controller: FullWorkspaceController;
  onOpenApp: (id: string) => void;
  onOpenBoundedApp: (id: string) => void;
  onChooseTemplate?: () => void;
  onResumeDraft?: (id: string, engine: "appspec.v1" | "bounded.v1") => void;
}
export function FullLauncher({
  controller,
  onOpenApp,
  onOpenBoundedApp,
  onResumeDraft,
}: FullLauncherProps) {
  const state = useSyncExternalStore(
      controller.subscribe,
      controller.getSnapshot,
      controller.getSnapshot,
    ),
    [name, setName] = useState(""),
    [starters, setStarters] = useState(false),
    [pinnedOnly, setPinnedOnly] = useState(false);
  useEffect(() => {
    void controller.load();
  }, [controller]);
  const locked = state.busy || !!state.pending;
  const open = (engine: string, id: string) =>
    engine === "appspec.v1" ? onOpenApp(id) : onOpenBoundedApp(id);
  if (state.historical)
    return (
      <View style={styles.screen}>
        <View style={[styles.row, { padding: 12 }]}>
          <Button
            label="Back to version history"
            variant="secondary"
            onPress={() => controller.closeHistorical()}
          />
          <Text style={styles.title}>
            {state.historical.summary.name} · version{" "}
            {state.historical.summary.number}
          </Text>
        </View>
        <Notice text="Read-only immutable definition rendered with isolated synthetic records. This is not a historical snapshot of live data. No effects, access or records are restored." />
        <IsolatedPreview spec={state.historical.spec} />
      </View>
    );
  return (
    <KeyboardAvoidingView
      style={styles.screen}
      behavior={Platform.OS === "ios" ? "padding" : undefined}
    >
      <ScrollView
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={styles.content}
      >
        <View style={styles.row}>
          <View style={{ flex: 1 }}>
            <Text style={styles.label}>Tinkerloom · Your workspace</Text>
            <Text accessibilityRole="header" style={styles.heading}>
              Small tools, woven together.
            </Text>
          </View>
          <Button
            label="Refresh workbench"
            variant="secondary"
            disabled={state.loading || state.busy}
            onPress={() => {
              void controller.load();
            }}
          />
        </View>
        {state.error && <Notice text={state.error} error />}
        {state.loading && (
          <Text accessibilityLiveRegion="polite" style={styles.muted}>
            Loading current accessible apps…
          </Text>
        )}
        {state.pending && (
          <Card title="A workbench request is retained">
            <Text style={styles.body}>
              {state.pendingStatus === "sending"
                ? "Saving…"
                : state.pendingStatus === "uncertain"
                  ? "The result is still unconfirmed."
                  : "The server rejected this change."}
            </Text>
            <Text style={styles.muted}>
              Original workspace: {String(state.pending.context.workspaceId)}.
              The original app ID, template or source version, and operation
              remain locked until their outcome is resolved. Leaving does not
              undo a request.
            </Text>
            {state.pendingStatus === "uncertain" && (
              <Button
                label="Check original workbench outcome"
                disabled={state.busy}
                onPress={() => {
                  void controller.retry();
                }}
              />
            )}
            {state.pendingStatus === "rejected" && (
              <Button
                label="Acknowledge definitive rejection"
                disabled={state.busy}
                onPress={() => {
                  void controller.acknowledgeRejection();
                }}
              />
            )}
          </Card>
        )}
        {state.createdAppId && (
          <Card title="App created">
            <Text style={styles.body}>
              The new app contains its own definition. No records, grants, jobs,
              claims or reminder approvals were copied.
            </Text>
            <Button
              label="Open created app"
              onPress={() => onOpenApp(state.createdAppId!)}
            />
            <Button
              label="Dismiss"
              variant="quiet"
              onPress={() => controller.clearCreated()}
            />
          </Card>
        )}
        <Card title="Start something useful">
          <Field
            label="New app name"
            value={name}
            editable={!locked}
            maxLength={120}
            onChangeText={setName}
          />
          <View style={styles.row}>
            <Button
              label="Create private builder shell"
              disabled={locked || !name.trim()}
              onPress={() => {
                void controller.create(name);
              }}
            />
            <Button
              label={
                starters
                  ? "Hide starter templates"
                  : "Choose a starter template"
              }
              variant="secondary"
              onPress={() => setStarters(!starters)}
            />
          </View>
          <Text style={styles.muted}>
            A builder shell starts without a placeholder definition. Starters
            create independent version 1 with no sample records or enabled
            effects.
          </Text>
          {starters &&
            fullTemplates.map((template) => (
              <View key={template.id} style={styles.card}>
                <Text style={styles.title}>{template.spec.name}</Text>
                <Text style={styles.body}>{template.caption}</Text>
                <Button
                  label={`Create ${template.spec.name}`}
                  variant="secondary"
                  disabled={locked}
                  onPress={() => {
                    void controller.instantiate(template.id);
                  }}
                />
              </View>
            ))}
        </Card>
        <Card title="Resume your private drafts">
          <Text style={styles.muted}>
            Only your own unconsumed drafts with current editor access appear
            here.
          </Text>
          {state.drafts.length === 0 && !state.loading && (
            <Text style={styles.body}>No private drafts to resume.</Text>
          )}
          {state.drafts.map((draft) => (
            <View key={draft.appId} style={styles.card}>
              <Text style={styles.title}>{draft.name}</Text>
              <Text style={styles.muted}>
                Revision {draft.revision}
                {draft.stale
                  ? " · Published version changed; review the base before publishing"
                  : ""}
              </Text>
              <Button
                label={`Resume ${draft.name}`}
                variant="secondary"
                onPress={() =>
                  onResumeDraft
                    ? onResumeDraft(draft.appId, draft.engine)
                    : open(draft.engine, draft.appId)
                }
              />
            </View>
          ))}
          {state.draftCursor && (
            <Button
              label="Load more private drafts"
              variant="secondary"
              disabled={state.loading}
              onPress={() => {
                void controller.loadMore("drafts");
              }}
            />
          )}
        </Card>
        <View style={styles.row}>
          <Text accessibilityRole="header" style={styles.title}>
            Apps you can access
          </Text>
          <Toggle
            label="Show pinned among loaded apps"
            value={pinnedOnly}
            onChange={setPinnedOnly}
          />
        </View>
        {state.apps.length === 0 && !state.loading && (
          <Notice text="No accessible apps in this workspace yet." />
        )}
        {state.apps
          .filter((app) => !pinnedOnly || app.pinned)
          .map((app) => (
            <Card key={app.id} title={app.name}>
              <Text style={styles.muted}>
                {app.role} ·{" "}
                {app.engine === "appspec.v1"
                  ? `Version ${app.version?.number ?? "not published"}`
                  : "Classic records app"}
                {app.archived ? " · Archived" : ""}
              </Text>
              <Text style={styles.body}>
                {app.recordCount} live records
                {app.availablePlaces === null
                  ? ""
                  : ` · ${app.availablePlaces} available places`}
              </Text>
              <View style={styles.row}>
                <Button
                  label={`Open ${app.name}`}
                  onPress={() => open(app.engine, app.id)}
                />
                <Button
                  label={app.pinned ? `Unpin ${app.name}` : `Pin ${app.name}`}
                  variant="secondary"
                  disabled={locked}
                  onPress={() => {
                    void controller.setPinned(app, !app.pinned);
                  }}
                />
                {app.engine === "appspec.v1" && app.version && (
                  <>
                    <Button
                      label="Version history"
                      variant="secondary"
                      onPress={() => {
                        void controller.history(app.id);
                      }}
                    />
                    <Button
                      label="Remix current version"
                      variant="secondary"
                      disabled={locked}
                      onPress={() => {
                        void controller.remix(app.id, app.version!.id);
                      }}
                    />
                  </>
                )}
              </View>
            </Card>
          ))}
        {state.cursor && (
          <Button
            label="Load more apps"
            variant="secondary"
            disabled={state.loading}
            onPress={() => {
              void controller.loadMore("apps");
            }}
          />
        )}
        {state.cursor && (
          <Text style={styles.muted}>
            More accessible apps are available. The pinned filter applies to
            loaded apps only.
          </Text>
        )}
        {state.historyAppId && (
          <Card title="Immutable version history">
            <Text style={styles.muted}>
              Definitions only. Viewing a version does not mutate records,
              publish, restore effects or change access.
            </Text>
            {state.versions.map((version) => (
              <View key={version.id} style={styles.card}>
                <Text style={styles.title}>
                  Version {version.number} · {version.name}
                </Text>
                <Text selectable style={styles.muted}>
                  {version.id}
                  {"\n"}
                  {version.hash}
                  {"\n"}
                  {version.createdAt ?? "Creation time unavailable"}
                </Text>
                <Button
                  label={`Inspect version ${version.number}`}
                  variant="secondary"
                  onPress={() => {
                    void controller.inspectVersion(
                      state.historyAppId!,
                      version.id,
                    );
                  }}
                />
              </View>
            ))}
            {state.versionCursor !== null && (
              <Button
                label="Load older versions"
                variant="secondary"
                disabled={state.loading}
                onPress={() => {
                  void controller.history(state.historyAppId!, true);
                }}
              />
            )}
            <Button
              label="Close history"
              variant="quiet"
              onPress={() => controller.closeHistory()}
            />
          </Card>
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
