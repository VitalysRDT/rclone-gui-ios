# App Store screenshots

Reproducible pipeline that produces the localized App Store screenshots from the
**real app UI** (Guideline 2.3.3 — Accurate Metadata), framed with marketing copy.

Sizes produced:
- **iPhone 6.9"** — 1320 × 2868 (captured on *iPhone 17 Pro Max* sim)
- **iPad 13"** — 2064 × 2752 (captured on *iPad Pro 13-inch (M5)* sim)

8 frames per device, in all App Store listing languages: `en-US`, `fr-FR`,
`de-DE`, `es-ES`, `it`, `ko`, `pl`, `zh-Hans`. The FR/EN frames embed FR/EN app
UI; the other languages reuse the **English** screenshots with translated
marketing headlines.

## The 8 frames

| # | demo-screen | Real surface | Headline (EN) |
|---|-------------|--------------|---------------|
| 1 | `files`    | Files / remotes list | Every cloud. Encrypted. |
| 2 | `wizard`   | Add-remote backend catalog | 80+ services. One home. |
| 3 | `folder`   | Folder browser (Photos) | Filenames decrypted on the fly. |
| 4 | `file`     | File detail (stream) | Stream direct. No full download. |
| 5 | `home`     | Home dashboard | Your control center. |
| 6 | `import`   | Import rclone.conf | Guided setup. |
| 7 | `photos`   | Photo-sync settings | Smart photo backup. |
| 8 | `security` | Security settings | Zero trackers. Zero servers. |

## How it works

1. **Simulator slice** — the app links `RcloneKit.xcframework`, which ships only
   device + macOS slices. To run on the simulator, rebuild it so it also
   contains an `ios-arm64-simulator` slice (add a `gomobile bind
   -target=iossimulator/arm64` pass to `scripts/build-rclone.sh`). This slice is
   for local screenshotting only and is **not** committed / shipped.
2. **Demo data** — `Rclone GUI/Core/DemoSeeder.swift` (DEBUG only) seeds a
   privacy-safe `rclone.conf` (alias + B2/S3/Drive/Dropbox/OneDrive/SFTP/crypt),
   a demo file tree, and SwiftData rows, when launched with `--seed-demo`.
3. **Deep links** — `MainTabView.swift` (DEBUG only) reads `--demo-screen <id>`
   to land directly on each surface. Onboarding and the Face ID gate are
   bypassed with `-hasCompletedOnboarding YES` and
   `-security.requireBiometricsAtLaunch NO`.
4. **Framing** — `compose-frames.py` renders each marketing frame (gradient,
   kicker pill, headline, decor) around the real screenshot with Chrome headless
   at exact App Store pixel sizes.

## Run

```bash
# 1. Build the app for the simulator (needs the ios-arm64-simulator slice)
xcodebuild -project "Rclone GUI.xcodeproj" -scheme "Rclone GUI" \
  -configuration Debug -sdk iphonesimulator -derivedDataPath build/dd build

# 2. Capture + frame + deploy into fastlane/screenshots/
APP_PATH="build/dd/Build/Products/Debug-iphonesimulator/RcloneGUI.app" \
  ./scripts/screenshots/capture.sh

# 3. Upload (needs an App Store Connect API key, see fastlane/Fastfile)
bundle exec fastlane upload_screenshots
```

`fastlane/screenshots/**/*.png` is git-ignored — regenerate locally before
uploading.
