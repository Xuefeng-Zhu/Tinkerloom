import { router } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { colors, space } from "./src/components/theme";
import { AuthScreen } from "./src/screens/AuthScreen";
import { HomeScreen } from "./src/screens/HomeScreen";
import { CreateSheet } from "./src/screens/CreateSheet";
import { useAppContext } from "./src/state/AppContext";

function SetupScreen() {
  return (
    <View style={styles.setup}>
      <View style={styles.setupContent}>
        <Text style={styles.eyebrow}>TINKERLOOM</Text>
        <Text accessibilityRole="header" style={styles.title}>
          Small tools.{"\n"}Made your way.
        </Text>
        <Text style={styles.body}>
          A notebook, a reading list, a place to get things done. Explore a few
          little apps and make them yours.
        </Text>
        <Pressable
          accessibilityRole="button"
          onPress={() => router.push("/preview")}
          style={({ pressed }) => [styles.primary, pressed && styles.pressed]}
        >
          <Text style={styles.primaryText}>Explore templates →</Text>
        </Pressable>
        <View style={styles.callout}>
          <Text style={styles.calloutTitle}>Cloud connection pending</Text>
          <Text style={styles.small}>
            Account sign-in and saved app shells will be available once this
            build is connected to Appwrite. Template previews use sample data on
            this screen.
          </Text>
        </View>
      </View>
    </View>
  );
}

export function AppScreen() {
  const { controller, state } = useAppContext();
  if (!controller || !state) return <SetupScreen />;
  if (state.phase === "loading") {
    return (
      <View style={styles.setup}>
        <Text accessibilityLiveRegion="polite" style={styles.body}>
          Opening Tinkerloom…
        </Text>
      </View>
    );
  }
  if (state.phase === "signedOut") {
    return (
      <AuthScreen
        busy={state.authBusy}
        error={state.error}
        onSignIn={(email, password) =>
          controller.authenticate("signIn", email, password)
        }
        onSignUp={(email, password, name) =>
          controller.authenticate("signUp", email, password, name)
        }
        onPreview={() => router.push("/preview")}
        onRestoreSession={() => {
          void controller.bootstrap();
        }}
      />
    );
  }
  return (
    <View style={styles.fill}>
      {state.notice && (
        <Text accessibilityLiveRegion="polite" style={styles.notice}>
          {state.notice}
        </Text>
      )}
      {state.creation?.command && !state.creation.open && (
        <View style={styles.recovery}>
          <Text style={styles.small}>
            A save is still unconfirmed. Review it before creating something
            else.
          </Text>
          <Pressable
            accessibilityRole="button"
            style={styles.recoveryButton}
            onPress={() => controller.openCreation(state.creation!.kind)}
          >
            <Text style={styles.link}>Review save</Text>
          </Pressable>
        </View>
      )}
      <HomeScreen
        user={state.user!}
        workspaces={state.workspaces}
        workspaceId={state.workspaceId}
        apps={state.apps}
        loading={state.loading || state.authBusy}
        error={state.error}
        onSelectWorkspace={(id) => {
          void controller.selectWorkspace(id);
        }}
        onRefresh={() => {
          void controller.refresh();
        }}
        onCreateWorkspace={() => controller.openCreation("workspace")}
        onCreateApp={() => controller.openCreation("app")}
        onSignOut={() => {
          void controller.signOut();
        }}
        onPreview={() => router.push("/preview")}
      />
      {state.creation?.open && (
        <CreateSheet
          kind={state.creation.kind}
          busy={state.creation.busy}
          error={state.creation.error}
          submittedName={state.creation.command?.name}
          workspaceName={
            state.workspaces.find(
              (workspace) =>
                workspace.id ===
                (state.creation?.command?.workspaceId ?? state.workspaceId),
            )?.name
          }
          onSubmit={(name) => {
            void controller.submitCreation(name);
          }}
          onCancel={() => controller.closeCreation()}
        />
      )}
    </View>
  );
}

export default function App() {
  return <AppScreen />;
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.canvas },
  setup: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    padding: space.lg,
    backgroundColor: colors.canvas,
  },
  setupContent: { maxWidth: 560, width: "100%", gap: space.lg },
  eyebrow: {
    fontSize: 12,
    fontWeight: "800",
    letterSpacing: 3,
    color: colors.accent,
  },
  title: {
    fontSize: 44,
    lineHeight: 50,
    fontWeight: "700",
    color: colors.ink,
    letterSpacing: -1,
  },
  body: { fontSize: 18, lineHeight: 28, color: colors.muted },
  primary: {
    minHeight: 52,
    justifyContent: "center",
    alignItems: "center",
    padding: space.md,
    borderRadius: 12,
    backgroundColor: colors.ink,
  },
  primaryText: { fontSize: 16, fontWeight: "700", color: colors.surface },
  pressed: { opacity: 0.8 },
  callout: {
    padding: space.md,
    backgroundColor: colors.sage,
    borderRadius: 12,
    gap: space.sm,
  },
  calloutTitle: { fontSize: 15, fontWeight: "700", color: colors.ink },
  small: { fontSize: 14, lineHeight: 21, color: colors.muted },
  notice: {
    padding: space.md,
    backgroundColor: colors.sage,
    color: colors.ink,
  },
  recovery: {
    padding: space.md,
    gap: space.xs,
    backgroundColor: colors.accentSoft,
  },
  recoveryButton: {
    minHeight: 44,
    justifyContent: "center",
    alignSelf: "flex-start",
  },
  link: { color: colors.accent, fontWeight: "700", fontSize: 15 },
});
