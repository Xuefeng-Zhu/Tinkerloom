import { useState } from "react";
import { Text, View } from "react-native";
import { Button } from "../components/Button";
import { Notice } from "../components/Notice";
import { runtimeError } from "../runtime/errors";
import {
  applyClarificationSelections,
  originalClarificationRequest,
  selectClarificationAnswer,
  type ClarificationAssessment,
  type ClarificationSelections,
} from "./clarification";
import { Card, Choices, styles } from "./ui";

export function ClarificationPanel({
  assessment,
  loading,
  currentRequest,
  disabled,
  onUse,
  onContinue,
  onBuiltIn,
}: {
  assessment: ClarificationAssessment | null;
  loading: boolean;
  currentRequest: string;
  disabled: boolean;
  onUse: (request: string) => void;
  onContinue: (request: string) => void;
  onBuiltIn: () => void;
}) {
  const [local, setLocal] = useState<{
    assessment: ClarificationAssessment | null;
    selections: ClarificationSelections;
    notice: string | null;
  }>({ assessment: null, selections: {}, notice: null });
  const session =
    local.assessment === assessment
      ? local
      : { assessment, selections: {}, notice: null };
  if (loading)
    return (
      <Card title="Checking your idea">
        <Text accessibilityLiveRegion="polite" style={styles.body}>
          Checking for useful clarification. No app or generation job is created
          by this check.
        </Text>
        <Button
          label="Continue with original request"
          variant="secondary"
          disabled={disabled}
          onPress={() => onContinue(currentRequest)}
        />
      </Card>
    );
  if (!assessment) return null;
  const current = assessment.requestText === currentRequest;
  return (
    <Card
      title={
        assessment.ready
          ? "Ready to continue"
          : assessment.source === "built-in"
            ? "Built-in questions"
            : "A few details would help"
      }
    >
      <Text accessibilityLiveRegion="polite" style={styles.body}>
        {assessment.notice}
      </Text>
      {!current && (
        <Notice text="Your idea changed. Ask for fresh questions before using selections." />
      )}
      {assessment.questions.map((question, i) => (
        <View key={`${i}:${question.question}`} style={{ gap: 8 }}>
          <Choices
            label={question.question}
            values={question.options}
            value={
              Object.hasOwn(session.selections, i)
                ? question.options[session.selections[i]]
                : ""
            }
            disabled={disabled || !current}
            onChange={(answer) => {
              setLocal({
                assessment,
                selections: selectClarificationAnswer(
                  assessment,
                  session.selections,
                  i,
                  question.options.indexOf(answer),
                ),
                notice: null,
              });
            }}
          />
          {Object.hasOwn(session.selections, i) && (
            <Button
              label={`Skip question ${i + 1}`}
              variant="quiet"
              disabled={disabled || !current}
              onPress={() => {
                const next = { ...session.selections };
                delete next[i];
                setLocal({ assessment, selections: next, notice: null });
              }}
            />
          )}
        </View>
      ))}
      {session.notice && <Notice text={session.notice} error />}
      <View style={styles.row}>
        {assessment.ready && (
          <Button
            label="Show optional built-in questions"
            variant="secondary"
            disabled={disabled || !current}
            onPress={onBuiltIn}
          />
        )}
        {assessment.questions.length > 0 && (
          <Button
            label="Use selections"
            disabled={
              disabled ||
              !current ||
              Object.keys(session.selections).length === 0
            }
            onPress={() => {
              try {
                onUse(
                  applyClarificationSelections(
                    assessment,
                    currentRequest,
                    session.selections,
                  ),
                );
              } catch (error) {
                setLocal({
                  ...session,
                  assessment,
                  notice: runtimeError(error).message,
                });
              }
            }}
          />
        )}
        <Button
          label="Continue with original request"
          variant="secondary"
          disabled={disabled || !current}
          onPress={() => {
            try {
              onContinue(
                originalClarificationRequest(assessment, currentRequest),
              );
            } catch (error) {
              setLocal({
                ...session,
                assessment,
                notice: runtimeError(error).message,
              });
            }
          }}
        />
      </View>
      <Text style={styles.muted}>
        {assessment.ready
          ? "Continue returns to the editable composer. Creating or generating remains a separate action."
          : "Choosing answers does not change your request. Use selections only prepares editable text; creating or generating remains a separate action."}
      </Text>
    </Card>
  );
}
