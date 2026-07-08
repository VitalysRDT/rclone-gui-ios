fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Push localized metadata (no binary, no screenshots) to App Store Connect

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Push screenshots only

### ios resubmit

```sh
[bundle exec] fastlane ios resubmit
```

Resubmit existing binary for review after metadata fixes (no rebuild)

### ios ship

```sh
[bundle exec] fastlane ios ship
```

Create the iOS version, attach already-uploaded build, push metadata, submit for review

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Full submission: archive + upload + send for review

----


## Mac

### mac upload_mac

```sh
[bundle exec] fastlane mac upload_mac
```

Archive the macOS Release build (App Store) and upload to App Store Connect

### mac upload_mac_metadata

```sh
[bundle exec] fastlane mac upload_mac_metadata
```

Push localized metadata to the macOS App Store version

### mac upload_mac_screenshots

```sh
[bundle exec] fastlane mac upload_mac_screenshots
```

Push macOS screenshots only (en-US + fr-FR)

### mac submit_mac

```sh
[bundle exec] fastlane mac submit_mac
```

Submit the macOS version for review (build already uploaded)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
