//
//  PhotoSyncIntents.swift
//  Rclone GUI — AppIntents
//
//  Pause / Resume intents wired to the Dynamic Island buttons of the
//  PhotoSync Live Activity. Conform to `LiveActivityIntent` (NOT just
//  `AppIntent`) so iOS runs them in the *main app* process — without
//  that conformance, the intent would execute in the widget extension
//  process where `PhotoSyncService.shared` is a different instance with
//  no state.
//
//  These intents are deliberately `isDiscoverable = false` — they
//  shouldn't surface in the Shortcuts UI (the user has no business
//  scripting "Pause PhotoSync" outside the Live Activity context).
//

import AppIntents
import Foundation

// LiveActivityIntent et l'API ActivityKit sont iOS-only. Le projet
// supporte aussi macOS (Catalyst/AppKit), donc on garde les intents
// confinés derrière un `#if os(iOS)`.
#if os(iOS)
@available(iOS 17.0, *)
struct PausePhotoSyncIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mettre en pause la synchro Photos"
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        await PhotoSyncService.shared.pausePhotoSync()
        return .result()
    }
}

@available(iOS 17.0, *)
struct ResumePhotoSyncIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Reprendre la synchro Photos"
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        await PhotoSyncService.shared.resumePhotoSync()
        return .result()
    }
}
#endif
