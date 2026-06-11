# Contributing to Rclone GUI

Merci de votre intérêt ! / Thanks for your interest!

## Ground rules

- The code is licensed under **MPL-2.0**. By contributing, you agree that
  your contributions are licensed under the same terms.
- Every commit must be **signed off** (Developer Certificate of Origin):

  ```
  git commit -s -m "fix: …"
  ```

  The `Signed-off-by:` trailer certifies that you wrote the change or have
  the right to submit it under the project license
  (see <https://developercertificate.org>).

## Building

1. Xcode 26+ (the project also builds with the Xcode 27 beta), Go 1.22+.
2. Build the librclone xcframework once:

   ```bash
   ./scripts/build-rclone.sh
   ```

   This produces `Frameworks/RcloneKit.xcframework` (iOS arm64 + macOS arm64).
   Without it the app falls back to a mock rclone engine in DEBUG.
3. Open `Rclone GUI.xcodeproj` and build the `Rclone GUI` scheme.

## Tests

- Swift unit tests: `Rclone GUITests` (Swift Testing).
- Go bridge tests: `cd scripts/rclone-bridge && go test ./...`

Please run both before opening a PR, and add tests for any bug fix.

## Localization

User-facing strings are French-first (`sourceLanguage: fr`) in
`Rclone GUI/Localizable.xcstrings` with an English translation. Add both
when introducing new strings.

## Scope notes

- StoreKit products, App Store metadata and brand assets are **not** open to
  contribution (see [TRADEMARKS.md](TRADEMARKS.md)).
- Anything that sends user data off-device is out of scope by design: the
  app's core promise is that configs and keys never leave the device.
