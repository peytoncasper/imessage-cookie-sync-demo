import { timingSafeEqual } from "node:crypto";

export function bearerToken(authorizationHeader: string | undefined): string | undefined {
  const prefix = "Bearer ";
  if (!authorizationHeader?.startsWith(prefix)) return undefined;
  const token = authorizationHeader.slice(prefix.length);
  return token.length > 0 ? token : undefined;
}

export function hasValidBearerToken(
  authorizationHeader: string | undefined,
  expectedSecret: string,
): boolean {
  const token = bearerToken(authorizationHeader);
  if (!token) return false;

  const supplied = Buffer.from(token, "utf8");
  const expected = Buffer.from(expectedSecret, "utf8");

  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}
