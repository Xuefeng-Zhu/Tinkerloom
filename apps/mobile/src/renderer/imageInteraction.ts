import type { PickedImage } from "../runtime/types";

export interface FieldImageLifetime {
  active: boolean;
  imageBusy: boolean;
  finishInteraction: (() => void) | null;
}
export const createFieldImageLifetime = (): FieldImageLifetime => ({
  active: true,
  imageBusy: false,
  finishInteraction: null,
});
export function disposeFieldImageLifetime(lifetime: FieldImageLifetime) {
  lifetime.active = false;
  try {
    lifetime.finishInteraction?.();
  } finally {
    lifetime.finishInteraction = null;
  }
}

/** No native API or transport here: adapters remain responsible for scope/authorization. */
export async function selectFieldImage(
  lifetime: FieldImageLifetime,
  options: {
    beginInteraction?: () => (() => void) | null;
    pick: () => Promise<PickedImage | null>;
    upload: (image: PickedImage) => Promise<string>;
    commit: (assetId: string) => void;
    busy: (value: boolean) => void;
    error: (message: string | null) => void;
  },
): Promise<void> {
  if (!lifetime.active || lifetime.imageBusy) return;
  const release = options.beginInteraction?.();
  if (options.beginInteraction && !release) {
    options.error(
      "Finish or recover the current operation before choosing an image.",
    );
    return;
  }
  lifetime.imageBusy = true;
  let finished = false;
  const finish = () => {
    if (!finished) {
      finished = true;
      release?.();
    }
  };
  lifetime.finishInteraction = finish;
  let picked: PickedImage | null = null;
  try {
    options.error(null);
    options.busy(true);
    picked = await options.pick();
    if (!lifetime.active) return;
    if (picked) {
      const assetId = await options.upload(picked);
      if (lifetime.active) options.commit(assetId);
    }
  } catch {
    if (lifetime.active)
      options.error(
        "The image could not be uploaded. Your other values are retained.",
      );
  } finally {
    try {
      picked?.bytes.fill(0);
    } finally {
      lifetime.imageBusy = false;
      try {
        if (lifetime.active) options.busy(false);
      } finally {
        try {
          finish();
        } finally {
          if (lifetime.finishInteraction === finish)
            lifetime.finishInteraction = null;
        }
      }
    }
  }
}
