import { RuntimeError } from "../runtime/errors";

export interface CameraPermissionPort {
  get(): Promise<{ granted: boolean; canAskAgain: boolean }>;
  request(): Promise<{ granted: boolean }>;
}
/** A permission sheet never resumes a device write. A fresh explicit tap is required. */
export async function requireTorchPermission(
  port: CameraPermissionPort,
  assertCurrent: () => void = () => {},
) {
  assertCurrent();
  const permission = await port.get();
  assertCurrent();
  if (permission.granted) return;
  if (!permission.canAskAgain)
    throw new RuntimeError(
      "permission_denied",
      "Enable camera access in system settings to use the flashlight.",
    );
  const next = await port.request();
  assertCurrent();
  throw new RuntimeError(
    next.granted ? "inactive" : "permission_denied",
    next.granted
      ? "Camera access is enabled. Return to the app and turn the flashlight on explicitly."
      : "Camera access was not granted.",
  );
}
