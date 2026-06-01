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
        #if os(iOS) || os(macOS)
        PhotoSyncService.registerNotificationCategories()
        #endif
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
            SavedLocation.self,
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
            RootGateView {
                ContentView()
            }
                .task {
                    await MainActor.run {
                        TransferQueue.shared.attach(modelContext: sharedModelContainer.mainContext)
                        PhotoSyncService.shared.attach(modelContext: sharedModelContainer.mainContext)
                        TrashService.shared.attach(modelContext: sharedModelContainer.mainContext)
                        // Bootstrap StoreKit : résout les entitlements actuels et
                        // démarre l'écoute de Transaction.updates. Persiste le
                        // snapshot dans l'App Group pour gater l'extension FileProvider.
                        SubscriptionService.shared.bootstrap()
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
                    // Re-apply bandwidth ceiling and pause flag — rclone forgets
                    // both on restart. restoreFromPersistedState handles both
                    // and retries with backoff if the rclone Go runtime isn't
                    // listening yet, with LogService failure entries on giving up.
                    Task.detached(priority: .background) { @MainActor in
                        let mbps = UserDefaults.standard.double(forKey: "transfer.bandwidthLimitMBps")
                        let bytesPerSecond = Int64(mbps * 1024 * 1024)
                        await TransferQueue.shared.restoreFromPersistedState(bytesPerSecond: bytesPerSecond)
                    }
                    // Resume an interrupted photo full-sync if the previous run
                    // didn't drain the backlog. Without this, the user has to
                    // reopen Settings and tap "Synchroniser" after every cold
                    // start — exactly the symptom of "il faut tout le temps
                    // appuyer sur synchronisation".
                    Task.detached(priority: .background) { @MainActor in
                        // E7 : nettoie d'éventuelles Live Activities
                        // orphelines (app killée mid-sync au lancement
                        // précédent). À faire AVANT resumeIfNeeded qui
                        // pourrait en redémarrer une.
                        #if os(iOS)
                        if #available(iOS 16.2, *) {
                            await PhotoSyncLiveActivity.endOrphanActivities()
                        }
                        #endif
                        await PhotoSyncService.shared.resumeIfNeeded()
                    }
                    // Hygiène cache média : supprime les .partial-* > 24h
                    // et applique la limite LRU (5GB par défaut). Sans ça,
                    // un utilisateur qui regarde 100 films cumule des Go
                    // de cache orphelin jusqu'à saturer le device.
                    Task.detached(priority: .background) {
                        _ = try? await MediaCacheService.shared.cleanupStalePartials()
                        try? await MediaCacheService.shared.evictIfNeeded(reservingBytes: 0)
                    }
                    // Démarre le monitoring d'activité utilisateur : capte
                    // les taps globaux et throttle automatiquement la bande
                    // passante à 1MB/s pendant que l'utilisateur navigue,
                    // restaure la pleine vitesse après 5s d'inactivité. Évite
                    // que la sync photos sature CPU/réseau quand l'utilisateur
                    // veut juste consulter ses remotes.
                    await MainActor.run {
                        UserActivityMonitor.shared.start()
                    }
                    Task { @MainActor in
                        let center = NotificationCenter.default
                        for await note in center.notifications(named: .userActivityDidChange) {
                            let isActive = (note.userInfo?["isActive"] as? Bool) ?? false
                            let mbps = UserDefaults.standard.double(forKey: "transfer.bandwidthLimitMBps")
                            let bytes = Int64(mbps * 1024 * 1024)
                            await TransferQueue.shared.applyThrottleForUserActivity(
                                isActive: isActive,
                                userPreferredBytes: bytes
                            )
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        #endif
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
