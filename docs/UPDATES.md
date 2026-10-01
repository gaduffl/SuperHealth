# In-app updates

SuperHealth can update itself on Android: it looks for a newer release, downloads
the APK, checks it, and hands it to Android's package installer. Nothing is
downloaded or installed without a tap; the optional check at startup only looks.

Settings → **App updates** holds the card. Updates are device-wide, so the card
is hidden for profiles in easy mode — whoever set the device up turns easy mode
off to update, as with the portable backup.

## Sources

**GitHub** (default, `gaduffl/superhealth`) reads the repository's latest
non-draft, non-prerelease Release through the GitHub API, which is the route that
also works for a private repository. CI already publishes `superhealth-<version>.apk`
under a `v<version>` tag on every merge to `main`, so no extra release step exists.

A private repository needs an access token: a fine-grained personal access token
with **Contents: read** on that one repository. It is stored in Android encrypted
storage next to the AI keys, never exported or synced, and sent only to
`api.github.com`. GitHub answers the asset download with a redirect to a signed
URL on another host; the token is deliberately not forwarded there.

**Own server** reads a manifest — a small JSON file at an `https` URL:

```json
{
  "version": "0.43.0+72",
  "apk_url": "superhealth-0.43.0-72.apk",
  "sha256": "<64 hex characters>",
  "size": 52428800,
  "notes": "What changed",
  "published_at": "2026-10-01T08:00:00Z"
}
```

`version` and `sha256` are required. `apk_url` may be relative to the manifest.
An optional token is sent as `Authorization: Bearer …`, and only to the
manifest's own host.

## What is checked

- Every URL, including each redirect, must be `https`.
- The build number (`+72`) decides what is newer, because that is what Android
  enforces. A higher name with a lower or equal build number is not an update.
- The APK's size and SHA-256 are checked against the source before anything is
  handed to Android (GitHub publishes a digest per asset; a manifest must carry
  one). A mismatch discards the file.
- Android itself refuses an update signed with a different key, and a downgrade.
  That is the backstop, and why every build must use the same private key — see
  [Android signing](ANDROID_SIGNING.md).

## Installing

The first time, Android asks you to allow SuperHealth to *install unknown apps*.
The card explains this and opens the right page; coming back starts the download
by itself. The install itself is a `PackageInstaller` session streamed from the
app's cache (no `FileProvider`, no exposed file), followed by Android's own
confirmation sheet. SuperHealth restarts when it finishes.

## Not verified here

The Kotlin side (`ApkUpdater`, `InstallStatusReceiver`) is compiled only by the
release build, and the install session has never run on a device in CI. Treat
the first real update as its verification. Starting the confirmation sheet from
the receiver relies on SuperHealth being in front; if you switch away while the
install is being committed, Android may hold the sheet back until you return.
