export class AppSpecError extends Error {
  constructor(
    readonly code: string,
    readonly path: string,
    message: string,
  ) {
    super(`${message} (${path.slice(0, 180)})`);
    this.name = "AppSpecError";
  }
}
export function requireSpec(
  condition: unknown,
  path: string,
  message: string,
  code = "invalid_appspec",
): asserts condition {
  if (!condition) throw new AppSpecError(code, path, message);
}
