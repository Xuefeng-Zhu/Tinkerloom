import { canonicalJson } from "../spec/schema";
import { freezeValidated } from "../runtime/immutable";
import type { PrivateMediaController } from "./controller";
import type { MediaUploadContext } from "./types";
import { context, fail } from "./codec";

/** Attachment is a separate explicit form edit; it never saves a record. */
export async function attachReadyMedia(
  controller: PrivateMediaController,
  destination: MediaUploadContext,
  isCurrent: () => boolean,
  attach: (assetId: string) => void,
): Promise<boolean> {
  const captured = freezeValidated(context(destination));
  const matches = () =>
    isCurrent() &&
    canonicalJson(controller.currentContext()) === canonicalJson(captured);
  if (!matches()) fail("media_context_changed");
  const ready = await controller.poll();
  if (!ready) return false;
  // A status response for an old form cannot attach to a changed field/record.
  if (!matches()) fail("media_context_changed");
  attach(ready);
  return true;
}
