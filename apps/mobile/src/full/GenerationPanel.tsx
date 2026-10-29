import { useEffect, useState } from "react";
import { Text, View } from "react-native";
import { Button } from "../components/Button";
import { Field } from "../components/Field";
import { Notice } from "../components/Notice";
import type { FullAppController, FullAppState } from "./FullAppController";
import { Card, Toggle, styles } from "./ui";
import { ClarificationPanel } from "./ClarificationPanel";
export function GenerationPanel({
  controller,
  state,
}: {
  controller: FullAppController;
  state: FullAppState;
}) {
  const [scratch, setScratch] = useState(false);
  const request = state.generationRequest;
  const job = state.app?.generation,
    active =
      !!job && ["queued", "generating", "validating"].includes(job.status);
  useEffect(() => {
    if (!active) return;
    const timer = setInterval(() => {
      void controller.pollGeneration();
    }, 4000);
    return () => clearInterval(timer);
  }, [controller, active, job?.id]);
  const locked =
    state.busy || !!state.pending || state.loading || !controller.canBuild;
  if (!controller.canBuild) return null;
  return (
    <Card title={state.candidate ? "Refine with AI" : "Describe your app"}>
      <Text style={styles.body}>
        Describe the people, records and workflow you need. AI proposes a
        private declaration; you review and publish it yourself.
      </Text>
      {!state.platform ? (
        <Notice text="Checking AI availability…" />
      ) : (
        !state.platform.generation && (
          <Notice text="AI generation is not configured on this backend. Start from a template or use the manual editor." />
        )
      )}
      {state.preparedRequest && (
        <Notice text="Your planned idea was carried into this builder in memory only. Review or edit it, then choose Generate explicitly. It is not saved until you submit a generation request." />
      )}
      {state.preparedRequest && request !== state.preparedRequest && (
        <Button
          label="Use prepared idea"
          variant="secondary"
          disabled={locked}
          onPress={() =>
            controller.setGenerationRequest(state.preparedRequest!)
          }
        />
      )}
      <Field
        label="What would you like to build or change?"
        multiline
        value={request}
        editable={!locked}
        maxLength={16384}
        onChangeText={(value) => {
          controller.setGenerationRequest(value);
        }}
        hint="Generate and provider clarification send this text only when selected. Built-in questions stay local. Live records and device information are not included."
      />
      {state.candidate && (
        <Toggle
          label="Start a fresh candidate from this request"
          value={scratch}
          disabled={locked}
          onChange={(value) => {
            setScratch(value);
            controller.invalidateGuidance();
          }}
        />
      )}
      <View style={styles.row}>
        <Button
          label={active ? "Generation in progress" : "Generate private preview"}
          disabled={
            locked || active || !state.platform?.generation || !request.trim()
          }
          onPress={() => {
            void controller.generate(request, scratch);
          }}
        />
        <Button
          label="Help me clarify"
          variant="secondary"
          disabled={locked || state.guidanceLoading || !request.trim()}
          onPress={() => {
            void controller.requestGuidance(request, scratch);
          }}
        />
      </View>
      <ClarificationPanel
        assessment={state.guidance}
        loading={state.guidanceLoading}
        currentRequest={request}
        disabled={locked}
        onUse={(value) => {
          controller.setGenerationRequest(value);
        }}
        onContinue={(value) => {
          controller.setGenerationRequest(value);
        }}
        onBuiltIn={() => controller.useBuiltInGuidance()}
      />
      {job && (
        <View style={{ gap: 8 }}>
          <Text accessibilityLiveRegion="polite" style={styles.title}>
            {job.status}
          </Text>
          <Text style={styles.muted}>
            Attempt {job.attempts} of 3 · {job.mode} · Private candidate only
          </Text>
          {job.diagnostics.length > 0 && (
            <Notice text={job.diagnostics} error={job.status === "failed"} />
          )}
          <Button
            label="Check generation status"
            variant="secondary"
            disabled={state.busy || !!state.pending}
            onPress={() => {
              void controller.pollGeneration();
            }}
          />
          {job.status === "failed" &&
            job.mode === "edit" &&
            state.candidate && (
              <Button
                label="Keep previous valid candidate"
                variant="secondary"
                disabled={locked}
                onPress={() => {
                  void controller.keepPrevious();
                }}
              />
            )}
          {job.status === "failed" && (
            <Text style={styles.muted}>
              The previous valid candidate remains available. Checking status
              does not create a new request or provider attempt. A new
              generation request uses a new operation.
            </Text>
          )}
        </View>
      )}
    </Card>
  );
}
