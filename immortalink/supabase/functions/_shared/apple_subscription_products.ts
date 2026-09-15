// App Store Connect product IDs are public catalog identifiers, not secrets.
// Keep this allowlist shared by purchase validation and server notifications.
export function productMap(): Map<string, string> {
  return new Map([
    ["everroots.family.monthly", "everroot_family"],
    ["everroots.family.annual", "everroot_family"],
    ["everroots.legacy.monthly", "everroot_legacy"],
    ["everroots.legacy.annual", "everroot_legacy"],
  ]);
}
