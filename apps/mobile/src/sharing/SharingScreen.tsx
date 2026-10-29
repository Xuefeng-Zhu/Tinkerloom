import { useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { createURL } from "expo-linking";
import { setStringAsync } from "expo-clipboard";
import type { AppMember, GrantRole } from "../backend/types";
import { Button } from "../components/Button";
import { Field } from "../components/Field";
import { Notice } from "../components/Notice";
import { styles } from "../live/LiveAppScreen";
import { SharingController, SharingState } from "./SharingController";

const roles: { role: GrantRole; title: string; detail: string }[] = [
  { role: "viewer", title: "Viewer", detail: "Read the published app." },
  {
    role: "member",
    title: "Member",
    detail: "Use the actions allowed by this app's rules.",
  },
  {
    role: "builder",
    title: "Builder",
    detail: "Edit a private draft, publish versions, and manage sharing.",
  },
];

function RoleChoices({
  value,
  disabled,
  onChange,
  label,
}: {
  value: string;
  disabled: boolean;
  onChange: (role: GrantRole) => void;
  label: string;
}) {
  return (
    <View
      accessibilityRole="radiogroup"
      accessibilityLabel={label}
      style={styles.card}
    >
      {roles.map(({ role, title, detail }) => (
        <Pressable
          key={role}
          accessibilityRole="radio"
          accessibilityLabel={title}
          accessibilityState={{ checked: value === role, disabled }}
          aria-checked={value === role}
          aria-disabled={disabled}
          disabled={disabled}
          onPress={() => onChange(role)}
          style={{ paddingVertical: 10, gap: 4 }}
        >
          <Text style={styles.sectionTitle}>
            {value === role ? "● " : "○ "}
            {title}
          </Text>
          <Text style={styles.hint}>{detail}</Text>
        </Pressable>
      ))}
    </View>
  );
}

function MemberRow({
  member,
  disabled,
  canShare,
  canRevoke,
  userId,
  controller,
}: {
  member: AppMember;
  disabled: boolean;
  canShare: boolean;
  canRevoke: boolean;
  userId: string;
  controller: SharingController;
}) {
  return (
    <View style={styles.card}>
      <Text selectable style={styles.sectionTitle}>
        {member.actorId === userId ? "You" : "Account"} · {member.actorId}
      </Text>
      <Text style={styles.body}>Role: {member.role}</Text>
      {member.role !== "owner" && canShare && (
        <View style={styles.toolbar}>
          {roles.map(({ role, title }) => (
            <Button
              key={role}
              label={`Make ${title}`}
              variant="quiet"
              disabled={disabled || role === member.role}
              onPress={() => {
                void controller.changeRole(member, role);
              }}
            />
          ))}
        </View>
      )}
      {member.role !== "owner" && canRevoke && (
        <Button
          label="Remove access"
          variant="quiet"
          disabled={disabled}
          onPress={() => {
            void controller.changeRole(member, null);
          }}
        />
      )}
    </View>
  );
}

export function SharingScreen({
  state,
  controller,
  userId,
  onBack,
  onActivity,
}: {
  state: SharingState;
  controller: SharingController;
  userId: string;
  onBack: () => void;
  onActivity?: () => void;
}) {
  const [role, setRole] = useState<GrantRole>("viewer");
  const [recipient, setRecipient] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [copyNotice, setCopyNotice] = useState<string | null>(null);
  const [reviewArchive, setReviewArchive] = useState(false);
  const inactive = state.busy || state.loading || Boolean(state.pending);
  const canShare = state.app?.capabilities?.share === true;
  const canRevoke = state.app?.capabilities?.revokeAccess === true;
  const created = state.createdInvite;
  const url = created ? createURL(`/invite/${created.token}`) : null;
  function invite() {
    const account = recipient.trim();
    if (account && !/^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(account)) {
      setFormError(
        "Use the recipient's account ID, or leave this blank for a shareable invitation.",
      );
      return;
    }
    setFormError(null);
    setCopyNotice(null);
    void controller.invite(role, account || null);
  }
  return (
    <ScrollView
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
    >
      <View style={styles.toolbar}>
        <Button label="← App" variant="quiet" onPress={onBack} />
        {onActivity && state.app?.engine === "appspec.v1" && (
          <Button label="Activity" variant="quiet" onPress={onActivity} />
        )}
        <Button
          label="Refresh people"
          variant="quiet"
          disabled={state.busy || state.loading}
          onPress={() => {
            void controller.load();
          }}
        />
      </View>
      <Text style={styles.eyebrow}>BETTER TOGETHER</Text>
      <Text accessibilityRole="header" style={styles.title}>
        {state.app?.name ?? "People and sharing"}
      </Text>
      {state.error && <Notice error text={state.error} />}
      {state.notice && <Notice text={state.notice} />}
      {state.app?.archived && (
        <Notice text="This app is archived. You can still remove existing access, but cannot add people or change its records." />
      )}
      {state.pending && (
        <View style={styles.card}>
          <Text style={styles.sectionTitle}>
            {state.busy ? "Saving your change…" : "This change is unconfirmed"}
          </Text>
          <Text style={styles.body}>
            The original invitation, target, role, and version are retained for
            the same request.
          </Text>
          {!state.busy && (
            <Button
              label="Retry same change"
              onPress={() => {
                void controller.retry();
              }}
            />
          )}
        </View>
      )}
      {canShare && (
        <>
          <Text accessibilityRole="header" style={styles.sectionTitle}>
            Invite someone
          </Text>
          <RoleChoices
            value={role}
            disabled={inactive}
            onChange={setRole}
            label="Invitation role"
          />
          <Field
            label="Recipient account ID (optional)"
            hint="Leave blank for a shareable single-use link. A bound invitation can only be accepted by that account."
            value={recipient}
            onChangeText={setRecipient}
            editable={!inactive}
            autoCapitalize="none"
            maxLength={36}
          />
          {formError && <Notice text={formError} error />}
          <Button
            label="Create invitation"
            disabled={inactive}
            onPress={invite}
          />
        </>
      )}
      {created && url && (
        <View style={styles.card}>
          <Text style={styles.sectionTitle}>Your invitation link</Text>
          <Text style={styles.body}>
            {created.invitation.role} · Expires{" "}
            {new Date(created.invitation.expiresAt).toLocaleString()}
          </Text>
          <Text selectable style={styles.hint}>
            {url}
          </Text>
          <Text style={styles.hint}>
            Keep this link somewhere safe. It is shown only in this signed-in
            session.
          </Text>
          <Button
            label="Copy invitation link"
            variant="secondary"
            disabled={inactive}
            onPress={() => {
              setCopyNotice(null);
              void setStringAsync(url, { android: { isSensitive: true } }).then(
                (copied) =>
                  setCopyNotice(
                    copied
                      ? "Invitation link copied."
                      : "Copy was unavailable. Select the link to copy it.",
                  ),
                () =>
                  setCopyNotice(
                    "Copy was unavailable. Select the link to copy it.",
                  ),
              );
            }}
          />
          {copyNotice && <Notice text={copyNotice} />}
        </View>
      )}
      <Text accessibilityRole="header" style={styles.sectionTitle}>
        People with access
      </Text>
      {state.members.map((member) => (
        <MemberRow
          key={member.actorId}
          member={member}
          userId={userId}
          controller={controller}
          disabled={inactive}
          canShare={canShare}
          canRevoke={canRevoke}
        />
      ))}
      {state.memberCursor && (
        <Button
          label="Load more people"
          disabled={inactive}
          variant="quiet"
          onPress={() => {
            void controller.loadMore("members");
          }}
        />
      )}
      {canRevoke && (
        <>
          <Text accessibilityRole="header" style={styles.sectionTitle}>
            Invitations
          </Text>
          {state.invitations.map((invitation) => (
            <View key={invitation.id} style={styles.card}>
              <Text style={styles.sectionTitle}>
                {invitation.role} invitation
              </Text>
              <Text style={styles.hint}>
                {invitation.revoked
                  ? "Revoked"
                  : invitation.acceptedBy
                    ? "Accepted"
                    : "Pending"}{" "}
                · Expires {new Date(invitation.expiresAt).toLocaleString()}
              </Text>
              {invitation.recipientId && (
                <Text selectable style={styles.hint}>
                  For account {invitation.recipientId}
                </Text>
              )}
              {!invitation.revoked && !invitation.acceptedBy && (
                <Button
                  label="Revoke invitation"
                  variant="quiet"
                  disabled={inactive}
                  onPress={() => {
                    void controller.revoke(invitation.id);
                  }}
                />
              )}
            </View>
          ))}
          {state.invitationCursor && (
            <Button
              label="Load more invitations"
              disabled={inactive}
              variant="quiet"
              onPress={() => {
                void controller.loadMore("invitations");
              }}
            />
          )}
        </>
      )}
      {state.app?.capabilities?.archive && (
        <View style={styles.card}>
          <Text style={styles.sectionTitle}>Archive app</Text>
          <Text style={styles.body}>
            Archiving permanently stops edits and new invitations. Existing
            records remain readable, and access can still be removed.
          </Text>
          {!reviewArchive ? (
            <Button
              label="Review archive"
              variant="quiet"
              disabled={inactive}
              onPress={() => setReviewArchive(true)}
            />
          ) : (
            <>
              <Button
                label="Archive this app"
                disabled={inactive}
                onPress={() => {
                  setReviewArchive(false);
                  void controller.archive();
                }}
              />
              <Button
                label="Keep app active"
                variant="quiet"
                disabled={inactive}
                onPress={() => setReviewArchive(false)}
              />
            </>
          )}
        </View>
      )}
    </ScrollView>
  );
}
