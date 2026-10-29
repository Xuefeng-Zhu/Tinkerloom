# Inspector input lifetime and flush

Inspector text no longer resets to the last valid label on focus or clears before blur has a result. Each label/content input owns a local `InspectorTextDraft` keyed by its semantic target and control purpose. Invalid text and failed/unconfirmed saves remain visible for repair. A successful matching blur may release the local text to the authoritative value; a later focus, keystroke, identity/reset change or unmount fences that completion. Unmount clears the local raw value and subscriptions. No raw text enters host storage or an RPC through this helper.

A local input is unchecked while its semantic edit runs, then explicitly accepted or rejected. Mounted rejected inputs block save, flush and leaving even if a different valid semantic control clears the controller's general `editorError`. The mounted registry exposes only a boolean. Its subscription notifies controller subscribers from input callbacks/layout effects so route protection and `usePreventRemove` can recompute; there are no render-phase controller notifications. View/action/page selectors now use the same serialized inspector-transition queue as section/field/canvas selection.

`editorResetEpoch` changes for explicit Discard, explicit full declaration replacement, a clean authoritative content replacement, or access loss. Ordinary valid typing, first dirty state, validation failure, revision-only acknowledgment and a save of the same candidate do not reset inputs. Invalid local text survives background refresh until it is repaired or explicitly discarded. Stable target identities do not include dirty flags, error strings, draft revisions or save state.

`save()` and `flush()` join one in-flight save promise. They do not join unrelated busy operations, allocate a second operation ID, replay a retained unknown command or wait for a publication review. Flush succeeds only with active builder authority, valid mounted inputs, no unresolved/dirty state and a confirmed fresh manifest. A confirmed save receipt followed by failed refresh remains an unsuccessful flush.

## Required root integration

This isolated patch does not edit `FullAppScreen` or `navigation.ts`. Root must retain its `onFlush` wiring and pass both new props:

```tsx
<SpecEditor
  // Existing declaration/edit props remain.
  onFlush={() => controller.flush()}
  editorResetEpoch={state.editorResetEpoch}
  registerInputGuard={controller.registerEditorInputGuard}
/>
```

The stable registration method accepts `(guard, subscribe)` and returns cleanup. The `subscribe` callback carries only changes to the mounted invalid-input boolean; it carries no text. `controller.hasRejectedEditorInput` is a synchronous boolean getter, and `canLeave` includes it. Root navigation and external URL bridges should flush when `dirty || editorError || source.hasRejectedEditorInput`, then recheck current scope/lock state. Route-owner/unsaved protection must include that getter too. Avoid unconditional declaration flush for viewers/live-only readers: they do not have builder authority.

## Verification

Seventeen new pure lifecycle/domain/controller groups cover invalid blur/refocus/repair; unrelated control changes; exact unknown writes and locks; late focus/type/reset/identity/unmount; canonical values; joined autosave/blur/selection; unrelated review; refresh failure after acknowledgment; explicit epoch rules; background definition change; account disposal; and subscribed route-guard changes without raw text in controller state. The existing competing-save regression is strengthened for the new join contract: it checks that neither caller resolves before the durable gate, no network write occurs before persistence, both callers finish after the same save, and exactly one write occurs.

The composed isolated client suite passes all 577 tests, with no failures, skips or cancellations; typecheck, lint and owned-file formatting pass. B05 is composed unchanged as baseline support, as are the frozen inspector/navigation files outside this patch. Browser focus/blur, Back/Forward protection and native assistive-technology interaction are not established by these tests.

After root integration/export, reproduce in a real browser: enter an invalid blank app name, blur, refocus, and confirm the blank remains editable; correct it and blur to save; repeat and choose Discard to restore the saved name. Attempt inspector switching and host navigation while rejected raw input exists, including after another valid control changes. Confirm one save for blur plus selection, retained recovery for an unknown outcome, and no newer input overwritten by a late result. No persistent source writes, Git/Cloud/provider calls, dependency changes or native actions were performed for this patch.
