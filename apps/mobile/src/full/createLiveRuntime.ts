import { createHostStorage } from "../host/createHostStorage";
import type { HostScope } from "../host/scope";
import { ensure } from "../runtime/errors";
import type { RuntimeError } from "../runtime/errors";
import { FunctionRuntimeAdapter } from "../runtime/functionAdapter";
import { withInvalidation } from "../runtime/invalidation";
import type {
  WatchActivity,
  InvalidationStamp,
} from "../runtime/invalidationTypes";
import type { RuntimeTransport } from "../runtime/types";
import { withReminders } from "../notifications/withReminders";
import { withPrivateMedia } from "../media/adapter";
import type { MediaPorts } from "../media/types";
import type { FullManifest, PlatformCapabilities } from "./contracts";
import type { HostStorage } from "./FullAppController";

/** One real encrypted child host is shared by watch, reminder and media wrappers. */
export function createLiveRuntime(
  app: FullManifest,
  transport: RuntimeTransport,
  context: { host: HostStorage; platform: PlatformCapabilities | null },
  options: {
    newId(): string;
    isCurrent(): boolean;
    onManifestChange(stamp: InvalidationStamp): Promise<void> | void;
    onAccessFailure(error: RuntimeError): void;
    createHostStorage?(scope: HostScope): HostStorage;
    mediaPorts?: MediaPorts;
    watchActivity?: WatchActivity;
  },
) {
  const host = (options.createHostStorage ?? createHostStorage)(
    context.host.lifetime.scope,
  );
  try {
    ensure(
      host.lifetime !== context.host.lifetime &&
        host.lifetime.key === context.host.lifetime.key &&
        host.storage.lifetime === host.lifetime,
      "invalid_scope",
      "A separate encrypted runtime host is required.",
    );
    const stop = context.host.lifetime.onDispose(() => host.lifetime.dispose());
    host.lifetime.onDispose(stop);
    const current = () =>
      host.lifetime.active &&
      context.host.lifetime.active &&
      options.isCurrent();
    const onAccessFailure = (error: RuntimeError) => {
      if (current()) options.onAccessFailure(error);
    };
    const watched = withInvalidation(
      new FunctionRuntimeAdapter(app, transport),
      transport,
      host.lifetime,
      {
        capability: context.platform?.invalidations ?? null,
        activity: options.watchActivity,
        onManifestChange: (stamp) =>
          current() ? options.onManifestChange(stamp) : undefined,
        onAccessFailure,
      },
    );
    const reminders = withReminders(watched, transport, host.lifetime, {
      effects: context.platform?.effects ?? [],
    });
    const adapter = withPrivateMedia(reminders, transport, host.lifetime, {
      privateMedia: context.platform?.privateMedia === true,
      newId: options.newId,
      storage: host.storage,
      ports: options.mediaPorts,
      isCurrent: current,
      onAccessFailure,
    });
    const dispose = adapter.dispose.bind(adapter);
    let disposed = false;
    adapter.dispose = () => {
      if (disposed) return;
      disposed = true;
      try {
        dispose();
      } finally {
        host.lifetime.dispose();
      }
    };
    return adapter;
  } catch (error) {
    if (host.lifetime !== context.host.lifetime) host.lifetime.dispose();
    throw error;
  }
}
