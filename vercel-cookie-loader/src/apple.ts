/** Deployment identifiers are configuration, never another developer's account. */
export function appleIdentifiers(): { appID: string; clipID: string; clipBundleID: string } | undefined {
  const team = process.env.APPLE_TEAM_ID?.trim();
  const bundle = process.env.APP_BUNDLE_IDENTIFIER?.trim();
  if (!team || !/^[A-Z0-9]{10}$/.test(team)
      || !bundle || !/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(bundle)) return undefined;
  const clipBundleID = `${bundle}.Clip`;
  return { appID: `${team}.${bundle}`, clipID: `${team}.${clipBundleID}`, clipBundleID };
}
