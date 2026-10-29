import { Text, View } from "react-native";
import type { ConversationSnapshot } from "./conversation";
import { conversationOutcome } from "./conversation";
import { Card, styles } from "./ui";
/** Only the controller's accepted, authorized session projection enters this view. */
export function ConversationHistory({
  conversation,
}: {
  conversation: ConversationSnapshot;
}) {
  if (!conversation.entries.length) return null;
  return (
    <Card title="This builder session">
      <Text style={styles.muted}>
        Accepted requests and their observed outcomes stay in this session only.
        Reopening restores the latest saved job, not the earlier conversation.
      </Text>
      {conversation.omitted > 0 && (
        <Text style={styles.muted}>
          {conversation.omitted} earlier{" "}
          {conversation.omitted === 1 ? "request is" : "requests are"} no longer
          held in session memory.
        </Text>
      )}
      {conversation.entries.map((entry) => (
        <View key={entry.jobId} style={{ gap: 8 }}>
          <Text style={styles.label}>
            You ·{" "}
            {entry.origin === "restored"
              ? "Restored latest request"
              : "Accepted request"}
          </Text>
          <Text selectable style={styles.body}>
            {entry.requestText}
          </Text>
          <Text style={styles.label}>Tinkerloom</Text>
          <Text style={styles.body}>{conversationOutcome(entry)}</Text>
        </View>
      ))}
    </Card>
  );
}
