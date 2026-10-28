import { useState } from "react";
import { setStringAsync } from "expo-clipboard";
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import type { MiniApp, User, Workspace } from "../backend/types";
import { Brand } from "../components/Brand";
import { Button } from "../components/Button";
import { Notice } from "../components/Notice";
import { colors, space } from "../components/theme";

export interface HomeScreenProps {
  user: User;
  workspaces: Workspace[];
  workspaceId: string | null;
  apps: MiniApp[];
  loading: boolean;
  error: string | null;
  onSelectWorkspace: (id: string) => void;
  onRefresh: () => void;
  onCreateWorkspace: () => void;
  onCreateApp: () => void;
  onSignOut: () => void;
  onPreview: () => void;
  onOpenApp: (id: string) => void;
  onEnterInvitation: () => void;
}

export function HomeScreen({
  user,
  workspaces,
  workspaceId,
  apps,
  loading,
  error,
  onSelectWorkspace,
  onRefresh,
  onCreateWorkspace,
  onCreateApp,
  onSignOut,
  onPreview,
  onOpenApp,
  onEnterInvitation,
}: HomeScreenProps) {
  const workspace = workspaces.find((item) => item.id === workspaceId);
  const [copyNotice, setCopyNotice] = useState<{
    accountId: string;
    message: string;
  } | null>(null);
  function copyAccountId() {
    const accountId = user.id;
    setCopyNotice(null);
    void setStringAsync(accountId).then(
      (copied) =>
        setCopyNotice({
          accountId,
          message: copied
            ? "Account ID copied."
            : "Copy was unavailable. Select the account ID to copy it.",
        }),
      () =>
        setCopyNotice({
          accountId,
          message: "Copy was unavailable. Select the account ID to copy it.",
        }),
    );
  }
  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={styles.scroll}
      keyboardShouldPersistTaps="handled"
    >
      <View style={styles.frame}>
        <View style={styles.header}>
          <Brand />
          <Button
            label="Sign out"
            variant="quiet"
            onPress={onSignOut}
            disabled={loading}
          />
        </View>
        <View style={styles.intro}>
          <Text style={styles.eyebrow}>YOUR WORKBENCH</Text>
          <Text style={styles.heading} accessibilityRole="header">
            Room for your next little idea.
          </Text>
          <Text style={styles.description}>
            {user.name ? `Welcome, ${user.name}.` : "Welcome back."} Keep your
            tools together in a workspace.
          </Text>
          <Text style={styles.account} numberOfLines={2}>
            Signed in as {user.email}
          </Text>
          <View style={styles.accountCard}>
            <Text style={styles.accountLabel}>Your account ID</Text>
            <Text selectable style={styles.accountId}>
              {user.id}
            </Text>
            <Text style={styles.sectionDescription}>
              Share this ID with someone who wants to invite this account.
            </Text>
            <View style={styles.accountActions}>
              <Button
                label="Copy account ID"
                variant="secondary"
                onPress={copyAccountId}
              />
              <Button
                label="Open invitation"
                variant="quiet"
                onPress={onEnterInvitation}
              />
            </View>
            {copyNotice?.accountId === user.id && (
              <Text
                accessibilityLiveRegion="polite"
                style={styles.sectionDescription}
              >
                {copyNotice.message}
              </Text>
            )}
          </View>
        </View>
        {error && <Notice text={error} error />}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <View style={styles.sectionCopy}>
              <Text style={styles.sectionTitle} accessibilityRole="header">
                Workspaces
              </Text>
              <Text style={styles.sectionDescription}>
                A home for the things you make.
              </Text>
            </View>
            <Button
              label="New workspace"
              variant="secondary"
              onPress={onCreateWorkspace}
              disabled={loading}
            />
          </View>
          {loading && (
            <View
              style={styles.loading}
              accessibilityRole="progressbar"
              accessibilityLabel="Loading workspaces and apps"
            >
              <ActivityIndicator color={colors.ink} />
              <Text style={styles.loadingText}>Refreshing your workbench…</Text>
            </View>
          )}
          {workspaces.length > 0 ? (
            <View style={styles.workspaceList}>
              {workspaces.map((item) => (
                <Pressable
                  key={item.id}
                  accessibilityRole="tab"
                  accessibilityLabel={`Workspace ${item.name}`}
                  accessibilityState={{
                    selected: item.id === workspaceId,
                    disabled: loading,
                  }}
                  disabled={loading}
                  onPress={() => onSelectWorkspace(item.id)}
                  style={({ pressed }) => [
                    styles.workspace,
                    item.id === workspaceId && styles.selectedWorkspace,
                    pressed && styles.pressed,
                  ]}
                >
                  <View style={styles.workspaceIcon}>
                    <Text style={styles.workspaceInitial}>
                      {item.name.slice(0, 1).toUpperCase()}
                    </Text>
                  </View>
                  <Text style={styles.workspaceName}>{item.name}</Text>
                  {item.id === workspaceId && (
                    <Text style={styles.selectedLabel}>Selected</Text>
                  )}
                </Pressable>
              ))}
            </View>
          ) : !loading && !error ? (
            <View style={styles.empty}>
              <Text style={styles.emptyTitle}>Begin with a workspace</Text>
              <Text style={styles.emptyText}>
                Give your collection a name. You can create apps inside it next.
              </Text>
              <Button
                label="Create your first workspace"
                onPress={onCreateWorkspace}
              />
            </View>
          ) : null}
        </View>
        {workspace && (
          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <View style={styles.sectionCopy}>
                <Text style={styles.sectionTitle} accessibilityRole="header">
                  Apps
                </Text>
                <Text style={styles.sectionDescription}>
                  In {workspace.name}
                </Text>
              </View>
              <Button
                label="New app"
                onPress={onCreateApp}
                disabled={loading}
              />
            </View>
            <Text style={styles.migrationNote}>
              Open an app to customize its draft, publish a version, or use its
              live records.
            </Text>
            {apps.length > 0 ? (
              <View style={styles.appList}>
                {apps.map((app) => (
                  <Pressable
                    key={app.id}
                    accessibilityRole="button"
                    accessibilityLabel={`Open ${app.name}`}
                    onPress={() => onOpenApp(app.id)}
                    style={styles.appRow}
                  >
                    <View style={styles.appIcon}>
                      <Text style={styles.appGlyph} accessibilityElementsHidden>
                        ⌘
                      </Text>
                    </View>
                    <View style={styles.appCopy}>
                      <Text style={styles.appName}>{app.name}</Text>
                      <Text style={styles.appCaption}>
                        Open app and builder
                      </Text>
                    </View>
                    <Text style={styles.saved}>Open →</Text>
                  </Pressable>
                ))}
              </View>
            ) : !loading ? (
              <View style={styles.appEmpty}>
                <Text style={styles.emptyTitle}>
                  What would you like to make?
                </Text>
                <Text style={styles.emptyText}>
                  Start with a name, or explore a template with sample data
                  below.
                </Text>
              </View>
            ) : null}
          </View>
        )}
        <View style={styles.inspiration}>
          <View style={styles.sectionCopy}>
            <Text style={styles.inspirationLabel}>TRY SOMETHING SMALL</Text>
            <Text style={styles.sectionTitle} accessibilityRole="header">
              A few threads to start with
            </Text>
            <Text style={styles.sectionDescription}>
              Explore local template previews with sample data.
            </Text>
          </View>
          <Button
            label="Explore templates"
            variant="secondary"
            onPress={onPreview}
            disabled={loading}
          />
        </View>
        <View style={styles.footer}>
          <Text style={styles.footerText}>Tinkerloom · Your workbench</Text>
          <Button
            label="Refresh"
            variant="quiet"
            onPress={onRefresh}
            disabled={loading}
          />
        </View>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.canvas },
  scroll: { flexGrow: 1, alignItems: "center", padding: space.lg },
  frame: {
    width: "100%",
    maxWidth: 1056,
    gap: space.xl,
    paddingBottom: space.xl,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    flexWrap: "wrap",
    gap: space.md,
    paddingVertical: space.sm,
  },
  intro: { gap: space.sm, maxWidth: 720 },
  eyebrow: {
    color: colors.accent,
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 1.1,
  },
  heading: {
    color: colors.ink,
    fontSize: 36,
    lineHeight: 42,
    letterSpacing: -1.1,
    fontWeight: "700",
  },
  description: { color: colors.muted, fontSize: 16, lineHeight: 25 },
  account: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 20,
    marginTop: space.sm,
  },
  accountCard: {
    alignSelf: "stretch",
    gap: space.sm,
    padding: space.md,
    marginTop: space.sm,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    backgroundColor: colors.surface,
  },
  accountLabel: { color: colors.ink, fontSize: 14, fontWeight: "600" },
  accountId: { color: colors.ink, fontSize: 15, lineHeight: 23 },
  accountActions: { flexDirection: "row", flexWrap: "wrap", gap: space.sm },
  section: { gap: space.md },
  sectionHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    flexWrap: "wrap",
    gap: space.md,
  },
  sectionCopy: { flexGrow: 1, flexShrink: 1, gap: space.sm },
  sectionTitle: {
    color: colors.ink,
    fontSize: 22,
    fontWeight: "600",
    lineHeight: 29,
  },
  sectionDescription: { color: colors.muted, fontSize: 14, lineHeight: 21 },
  workspaceList: { flexDirection: "row", flexWrap: "wrap", gap: space.sm },
  workspace: {
    flexDirection: "row",
    alignItems: "center",
    gap: space.sm,
    padding: space.md,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    backgroundColor: colors.surface,
    minHeight: 68,
    maxWidth: "100%",
    flexShrink: 1,
  },
  selectedWorkspace: { borderColor: colors.ink, backgroundColor: colors.sage },
  workspaceIcon: {
    width: 32,
    height: 32,
    borderRadius: 8,
    backgroundColor: colors.surface,
    alignItems: "center",
    justifyContent: "center",
  },
  workspaceInitial: { color: colors.ink, fontWeight: "600", fontSize: 16 },
  workspaceName: {
    color: colors.ink,
    fontWeight: "600",
    fontSize: 15,
    flexShrink: 1,
  },
  selectedLabel: { color: colors.muted, fontSize: 11 },
  pressed: { opacity: 0.75 },
  loading: {
    flexDirection: "row",
    gap: space.sm,
    alignItems: "center",
    minHeight: 48,
  },
  loadingText: { color: colors.muted, fontSize: 14, flexShrink: 1 },
  empty: {
    alignItems: "flex-start",
    gap: space.md,
    borderWidth: 1,
    borderColor: colors.border,
    borderStyle: "dashed",
    borderRadius: 12,
    padding: space.lg,
  },
  emptyTitle: {
    color: colors.ink,
    fontSize: 18,
    fontWeight: "600",
    lineHeight: 25,
  },
  emptyText: {
    color: colors.muted,
    fontSize: 14,
    lineHeight: 22,
    maxWidth: 520,
  },
  migrationNote: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 20,
    maxWidth: 700,
  },
  appList: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    overflow: "hidden",
    backgroundColor: colors.surface,
  },
  appRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: space.md,
    padding: space.md,
    minHeight: 88,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  appIcon: {
    width: 44,
    height: 44,
    borderRadius: 10,
    backgroundColor: colors.accentSoft,
    alignItems: "center",
    justifyContent: "center",
  },
  appGlyph: { color: colors.accent, fontSize: 23 },
  appCopy: { flex: 1, gap: space.xs },
  appName: {
    color: colors.ink,
    fontSize: 16,
    fontWeight: "600",
    lineHeight: 23,
  },
  appCaption: { color: colors.muted, fontSize: 13 },
  saved: { color: colors.muted, fontSize: 12 },
  appEmpty: {
    padding: space.lg,
    gap: space.sm,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
  },
  inspiration: {
    flexDirection: "row",
    alignItems: "center",
    flexWrap: "wrap",
    gap: space.lg,
    padding: space.lg,
    backgroundColor: colors.sage,
    borderRadius: 16,
  },
  inspirationLabel: {
    color: colors.accent,
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 0.8,
  },
  footer: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    flexWrap: "wrap",
    gap: space.sm,
  },
  footerText: { color: colors.muted, fontSize: 12 },
});
