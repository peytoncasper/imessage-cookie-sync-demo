export type ErrorCode =
  | "BAD_REQUEST"
  | "UNAUTHORIZED"
  | "METHOD_NOT_ALLOWED"
  | "SESSION_NOT_FOUND"
  | "SESSION_NOT_RUNNING"
  | "SESSION_LIMIT_REACHED"
  | "BROWSERBASE_ERROR"
  | "CDP_ERROR"
  | "CONFIGURATION_ERROR";

export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: ErrorCode,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = "AppError";
  }
}
