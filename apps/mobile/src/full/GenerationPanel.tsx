import { useEffect, useRef, useState } from "react";
import { Text, View } from "react-native";
import { Button } from "../components/Button";
import { Field } from "../components/Field";
import { Notice } from "../components/Notice";
import type { FullAppController, FullAppState } from "./FullAppController";
import { Card, Toggle, styles } from "./ui";
export function GenerationPanel({
  controller,
  state,
}: {
  controller: FullAppController;
  state: FullAppState;
}) {
  const [request, setRequest] = useState(""),
    [scratch, setScratch] = useState(false);
  const previous = useRef<string | null>(null);
  const job = state.app?.generation,
    active =
      !!job && ["queued", "generating", "validating"].includes(job.status);
  useEffect(() => {
    if (job && job.id !== previous.current) {
      previous.current = job.id;
      setRequest(job.requestText);
    }
  }, [job]);
  useEffect(() => {
    if (!active) return;
    const timer = setInterval(() => {
      void controller.pollGeneration();
    }, 4000);
    return () => clearInterval(timer);
  }, [controller, active, job?.id]);
  const locked = state.busy || !!state.pending || !controller.canBuild;
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
      <Field
        label="What would you like to build or change?"
        multiline
        value={request}
        editable={!locked}
        maxLength={16384}
        onChangeText={(value) => {
          setRequest(value);
          controller.invalidateGuidance();
        }}
        hint="Your request goes to the backend provider. Live records and device information are not included."
      />
      {state.candidate && (
        <Toggle
          label="Start a fresh candidate from this request"
          value={scratch}
          disabled={locked}
          onChange={setScratch}
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
          disabled={
            locked ||
            !state.platform?.guidance ||
            !request.trim() ||
            request.length > 2000
          }
          onPress={() => {
            void controller.requestGuidance(request);
          }}
        />
      </View>
      {state.guidance?.map((q, i) => (
        <View key={`${i}:${q.question}`} style={{ gap: 8 }}>
          <Text style={styles.body}>{q.question}</Text>
          <View style={styles.row}>
            {q.options.map((answer, index) => (
              <Button
                key={`${index}:${answer}`}
                label={answer}
                variant="secondary"
                disabled={locked}
                onPress={() => {
                  setRequest((value) => `${value}\n${q.question}\n${answer}`);
                  controller.invalidateGuidance(true);
                }}
              />
            ))}
          </View>
        </View>
      ))}
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
