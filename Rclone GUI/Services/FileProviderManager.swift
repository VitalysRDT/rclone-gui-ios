//
//  FileProviderManager.swift
//  Rclone GUI — Services
//
//  Registers the single Rclone GUI FileProvider domain when the app
//  launches (and the extension target is enabled). Phase D v1 scope:
//  domain registration + signaling. The actual fetch/enumerate logic
//  lives in the extension target (FileProvider/).
//
//  IPC pattern (per PRD FR-045): the extension is a thin client. When
//  it needs bytes, it writes a request to the App Group container and
//  posts a Darwin Notification. The main app observes, fetches via
//  librclone, writes the file to the cache, and signals back.
//

import Foundation
#if canImport(FileProvider)
import FileProvider
#endif

@MainActor
public final class FileProviderManager {
    public static let shared = FileProviderManager()
    private init() {}

    public static let domainIdentifier = NSFileProviderDomainIdentifier("com.rougetet.rclone-gui.main")
    public static let domainDisplayName = "Rclone GUI"

    /// Register the single FileProvider domain. No-op if the extension
    /// target is not built or not provisioned.
    public func registerDomain() async {
        #if canImport(FileProvider)
        let domain = NSFileProviderDomain(
            identifier: Self.domainIdentifier,
            displayName: Self.domainDisplayName
        )
        do {
            try await NSFileProviderManager.add(domain)
        } catch {
            // Likely cases:
            // - Domain already registered (idempotent re-add)
            // - Extension not bundled or provisioning lacks the FileProvider entitlement
            // Silent fail in v1 — surface via Settings → Diagnostic in Phase E.
        }
        #endif
    }

    /// Signal that the cached enumeration for `<remote>:<path>` is stale.
    public func signalRefresh(remote: String, path: String = "") {
        #if canImport(FileProvider)
        let manager = NSFileProviderManager(for: NSFileProviderDomain(
            identifier: Self.domainIdentifier,
            displayName: Self.domainDisplayName
        ))
        let identifier = NSFileProviderItemIdentifier("\(remote):\(path)")
        manager?.signalEnumerator(for: identifier) { _ in }
        #endif
    }

    /// Tear down the domain (used by Settings → Reset).
    public func unregisterDomain() async {
        #if canImport(FileProvider)
        let domain = NSFileProviderDomain(
            identifier: Self.domainIdentifier,
            displayName: Self.domainDisplayName
        )
        try? await NSFileProviderManager.remove(domain)
        #endif
    }
}
