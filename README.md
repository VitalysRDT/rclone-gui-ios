# Rclone GUI

A native iOS & macOS client for [rclone](https://rclone.org) — browse, stream,
transfer and back up files across 80+ cloud storage backends (S3, R2, Google
Drive, Dropbox, SFTP, B2, crypt…), with your configuration encrypted on-device.

[**rclone.rougetet.com**](https://rclone.rougetet.com) · [Download on the App Store](https://apps.apple.com/app/id6770088773)

## Highlights

- **Privacy-first**: your `rclone.conf` is encrypted at rest (ChaChaPoly,
  key in the Keychain / Secure Enclave). Keys and credentials never leave
  the device — there is no backend.
- **Real rclone inside**: the actual rclone engine (v1.68) compiled to a
  native framework via gomobile — including full `crypt` support with
  on-the-fly decryption.
- **Encrypted configs supported**: imports `RCLONE_ENCRYPT_V0` configuration
  files (`rclone config encryption set`) with in-app password decryption.
- **Files.app integration**: every remote is exposed as a FileProvider domain.
- **PhotoSync**: opportunistic photo-library backup to any remote.
- **Streaming**: audio/video streaming through a loopback HTTP server,
  including from crypt remotes.

The app is paid (subscription) on the App Store; the source is open under
the MPL-2.0. Those two things are compatible: what you pay for is the signed,
auto-updating, officially supported build. You are free to build it yourself.

## Building

```bash
./scripts/build-rclone.sh        # builds Frameworks/RcloneKit.xcframework (Go ≥1.22)
open "Rclone GUI.xcodeproj"      # build the "Rclone GUI" scheme (Xcode 26+)
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for tests and guidelines.

## Version history

The full changelog lives at [rclone.rougetet.com/#versions](https://rclone.rougetet.com/#versions)
and in-app under **Settings → Version history**.

- **2.0** — Transparency, zero phone-home: a live in-app monitor + a reproducible,
  independently verifiable native build. Plus Handoff (transfer your encrypted config
  between devices via QR/AirDrop/file), Ghost Vault (encrypted config backup to a remote),
  smarter downloads (automatic network/battery/thermal management + reliable folder
  downloads), fixed iCloud Drive sign-in (regular Apple ID password + in-app 2FA prompt),
  and visible skipped photos in PhotoSync.
- **1.9.2** — Folder-download progress bar (folder size precomputed before the transfer).
- **1.9.1** — Fix: first-launch “rclone catalog unavailable” error when creating your first remote.
- **1.9** — Rebuilt video player (VLCKit 4: robust 4K MKV/HEVC, crackle-free audio),
  video Picture-in-Picture, more reliable “Open in another app”, and background audio.
- **1.8** — Pro Transfers: a queue with adjustable concurrency and drag-and-drop reordering.
- **1.7** — Download entire folders in one go (recursive).
- **1.6** — Connect with a file (SSH private key, service-account JSON, TLS cert…) imported straight from Files.
- **1.5** — Built-in multi-format video player (MKV, AVI, WebM, TS…) with subtitles and audio tracks.
- **1.4** — New clouds: Drime, Internxt and Filen (Internxt and Filen are end-to-end encrypted).
- **1.3** — Fix: importing a password-encrypted rclone configuration no longer crashes the app.
- **1.2** — Native macOS app (Apple Silicon): sidebar layout and Finder integration.
- **1.1** — Full English localization (follows your device language).
- **1.0** — First public release: native rclone client, 70+ backends, Files integration,
  end-to-end crypt encryption, photo sync, Face ID, zero tracking.

## License & trademarks

- Code: [MPL-2.0](LICENSE).
- Name, icon, screenshots, App Store listing and bundle identifiers are
  **not** covered by the license — see [TRADEMARKS.md](TRADEMARKS.md).
- “rclone” is a trademark of Nick Craig-Wood; this project is independent
  and not endorsed by the rclone project.

## Privacy

The privacy policy lives at
[vitalysrdt.github.io/rclone-gui-ios/privacy.html](https://vitalysrdt.github.io/rclone-gui-ios/privacy.html)
(source: [docs/privacy.md](docs/privacy.md)).
