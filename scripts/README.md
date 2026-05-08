# Build scripts

## `build-rclone.sh`

Builds `librclone` as an iOS `xcframework` via `gomobile bind`.

### Quick start

```bash
chmod +x scripts/build-rclone.sh
./scripts/build-rclone.sh                # build the default tag (v1.68.0)
./scripts/build-rclone.sh v1.69.0        # build a specific tag
```

### What it does

1. Verifies `go` ≥ 1.22 and Xcode CLT are installed
2. Auto-installs `gomobile` if missing (`go install golang.org/x/mobile/cmd/gomobile@latest`)
3. Runs `gomobile init` (idempotent — downloads iOS support code on first run)
4. Clones `rclone/rclone` at the requested tag into `.build/rclone`
5. Runs `gomobile bind -target=ios,iossimulator` → `Frameworks/RcloneKit.xcframework`
6. Ready to drag into Xcode

### Output

- `Frameworks/RcloneKit.xcframework` — multi-arch, ready to embed
- `.build/rclone/` — rclone source clone (cached for next builds, can be deleted to force re-clone)

### Build size

Typical output size:
- `arm64` slice : ~30–40 MB
- `arm64+x86_64` simulator slice : ~60–80 MB
- Total xcframework : ~90–120 MB on disk (fat) ; final IPA arm64-only ~30–40 MB after slicing

### Troubleshooting

- **`gomobile: command not found`** after install :
  ```bash
  export PATH="$PATH:$(go env GOPATH)/bin"
  ```

- **`xcrun: error: invalid active developer path`** :
  ```bash
  sudo xcode-select --reset
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```

- **`undefined symbol: ...` at build time in Xcode** :
  Probably the gomobile-generated symbol names differ from what `LibrcloneEngine.swift` expects. Inspect `Frameworks/RcloneKit.xcframework/ios-arm64/RcloneKit.framework/Headers/Librclone.objc.h` to see the actual exported function names, then update `LibrcloneEngine.swift` accordingly.

- **App size warning by App Store** :
  Use `arm64`-only slicing at archive time; the simulator slice is automatically stripped from the IPA.

### Updating the rclone version

Tags : <https://github.com/rclone/rclone/tags>

After updating, run the full integration test suite (`Rclone GUITests`) to catch any breaking changes in the librclone RPC interface.
