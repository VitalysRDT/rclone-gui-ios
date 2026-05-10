//
//  Rclone_GUIApp.swift
//  Rclone GUI
//

import SwiftUI
import SwiftData
import BackgroundTasks
import Darwin

@main
struct Rclone_GUIApp: App {
    init() {
        prepareRuntime()
        PhotoSyncService.shared.registerBackgroundTasks()
    }

    var sharedModelContainer: ModelContainer = {
        _ = try? AppGroup.prepareSharedContainerLayout()

        let schema = Schema([
            Remote.self,
            RemoteEntry.self,
            Transfer.self,
            TransferBatch.self,
            PhotoSyncAsset.self,
            TrashEntry.self,
        ])
        // Local-only store: explicitly opt out of SwiftData/CloudKit auto-sync.
        // The app declares the iCloud entitlement (for future iCloud Drive
        // document support, PRD Phase D+) but our @Model entities use unique
        // constraints and non-optional fields that CloudKit rejects. Without
        // .none here, SwiftData detects the entitlement and tries to mirror
        // every entity through CloudKit, crashing at container init.
        let modelConfiguration = ModelConfiguration(
            "RcloneGUI",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Last-resort recovery: nuke the on-disk store and retry once.
            // Old stores can fail to migrate (e.g. after a schema change or
            // the CloudKit-mirrored regression that just landed) — better
            // a fresh empty store than an unbootable app.
            let storeURL = modelConfiguration.url
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await MainActor.run {
                        TransferQueue.shared.attach(modelContext: sharedModelContainer.mainContext)
                        PhotoSyncService.shared.attach(modelContext: sharedModelContainer.mainContext)
                        TrashService.shared.attach(modelContext: sharedModelContainer.mainContext)
                    }
                    try? await ConfigStore.shared.migrateMasterKeyToSharedAccessGroupIfNeeded()
                    await LogService.emitBoot()
                    await FileProviderManager.shared.registerDomain()
                    await MainActor.run {
                        FileProviderFetchService.shared.start()
                    }
                    if let remotes = try? await RemoteService.shared.listRemoteSummaries() {
                        await FileProviderManager.shared.writeRemotesManifest(remotes)
                    }
                    PhotoSyncService.shared.scheduleBackgroundProcessing()
                    // Auto-purge trashed items past their 30-day retention. Runs in
                    // the background so a slow remote doesn't delay app launch.
                    // @MainActor annotation is required because TrashService is
                    // @MainActor-isolated and accesses sharedModelContainer.mainContext,
                    // which is bound to the main actor per SwiftData's threading contract.
                    Task.detached(priority: .background) { @MainActor in
                        await TrashService.shared.purgeExpired()
                    }
                    // Apply persisted bandwidth ceiling — rclone forgets it on
                    // restart, so we re-send it every boot. 0 means "off".
                    Task.detached(priority: .background) { @MainActor in
                        let mbps = UserDefaults.standard.double(forKey: "transfer.bandwidthLimitMBps")
                        let bytesPerSecond = Int64(mbps * 1024 * 1024)
                        try? await TransferQueue.shared.applyBandwidthLimit(bytesPerSecond: bytesPerSecond)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

private func prepareRuntime() {
    do {
        try AppGroup.prepareSharedContainerLayout()
        let workingDirectory = AppGroup.runtimeWorkingDirectoryURL
        _ = workingDirectory.path.withCString { chdir($0) }
        setenv("PWD", workingDirectory.path, 1)
        setenv("HOME", AppGroup.containerURL.path, 1)
        setenv("TMPDIR", NSTemporaryDirectory(), 1)
    } catch {
        let fallback = NSTemporaryDirectory()
        _ = fallback.withCString { chdir($0) }
        setenv("PWD", fallback, 1)
    }
}
