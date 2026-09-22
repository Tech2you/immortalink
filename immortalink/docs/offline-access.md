# Recently viewed offline copies

## Scope

The offline home is a directory headed Offline, with separate Vaults, Family
trees and Media sections. Successfully visited personal, shared and legacy
vaults can be opened here without network requests, even if connectivity returns.
Tree navigation remains available, but Open Vault buttons and edits are hidden.
Old photo entries with different refresh timestamps are consolidated by resource
URL without extending their original expiry; different image transforms remain
separate. No additional media is prefetched for offline browsing.

Native-device, read-only access in recently opened vault screens and via
Your Vault > Settings > Recently viewed. The normal vault route restores recent
profile metadata and stories; it does not require visiting the gallery first.
If the vault cannot load, its failure screen also provides a direct Recently
viewed action and a retry button. It never renders raw network/database errors.
Viewed media photos and successfully loaded family-tree metadata are cached
automatically. Videos, audio, AI, edits, uploads and complete vault histories
remain online-only. Tree portraits are not included in snapshots. A vault
snapshot includes the stories returned by its last successful load, not an
automatic download of every media file. Only viewed photos have offline bytes.

Foreground vault/editor screens check reachability every ten seconds and on
resume. Add memory and Preserve also check before proceeding. A connection loss
switches the vault to read-only; the editor retains typed text while open but
does not queue offline uploads. A network change between checking and sending
is still possible, so save errors also use safe public messages.

The subscription catalog retries after an unavailable store or empty catalog,
on resume and every twenty seconds while its failed pricing sheet is visible.
Product loading does not require a selected family, but purchasing still does.
Prices and entitlements remain Apple/server-authoritative; no fallback price or
local paid entitlement is introduced.

The cache holds up to 250 MiB of indexed payloads and 1,000 entries. Copies
expire six hours after a successful online fetch; viewing offline does not
extend expiry. Photos larger than 20 MiB retain online viewing but are not
cached. The OS may discard cached files at any time. This is not a backup.

## Privacy and access

- Stored in the application's private cache directory, not Photos or Documents.
- Only the current signed-in account can read entries. Switching accounts or
  signing out clears copies and invalidates in-flight writes.
- Explicit Clear offline storage does not delete server memories.
- A successful family-membership refresh that detects a lost membership clears
  all copies, conservatively, because photos may appear in several families.
- Leaving a family or detecting tree access denial also clears copies.
- Vault-load authentication/permission denial clears copies too; it is not
  classified as a connectivity failure. Concurrent vault reloads are suppressed.
- Normal photo loading uses the network first. HTTP 401/403/404/410 removes that
  cached photo; only transport failures and timeouts allow fallback.
- Offline tree snapshots cannot open vaults or add, rename, leave, or edit.
- Server deletion/access revocation cannot be discovered while disconnected.
  Recently viewed is explicitly a snapshot browser, not proof of current access.
- Active offline views check expiry once per minute; persisted timestamps are
  checked on every cache read. Device clock rollback expires affected entries.

No backend grants, RLS changes or subscription changes are required. This is
OS-private storage, not application-level encryption or an E2EE guarantee.

## Phone check

1. Stay signed in, open some photos and a family tree while online.
2. Open Settings > Recently viewed and confirm both appear.
3. Enable airplane mode, close and reopen the app, and return to Recently viewed.
4. Open a photo, zoom it, and browse the read-only tree. No edits should be enabled.
5. Clear offline storage. Copies disappear, including any open offline view.
6. Reconnect, view content again, then sign out and use a different account.
   No copies from the previous account should be visible.
7. With two test accounts, remove membership while the other is disconnected.
   Reconnect and refresh its vault. Its device cache should be cleared.

Automated tests cover LRU, expiry, account isolation, restart, malformed index,
oversize files, stale writes, online photo caching, offline fallback, denied
photo access, and read-only tree controls. Physical airplane-mode behavior
still requires the phone check above.
