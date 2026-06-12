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
