//
//  Rclone_GUIApp.swift
//  Rclone GUI
//

import SwiftUI
import SwiftData

@main
struct Rclone_GUIApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Remote.self,
            RemoteEntry.self,
            Transfer.self,
        ])
        // Local-only store: explicitly opt out of SwiftData/CloudKit auto-sync.
        // The app declares the iCloud entitlement (for future iCloud Drive
        // document support, PRD Phase D+) but our @Model entities use unique
        // constraints and non-optional fields that CloudKit rejects. Without
        // .none here, SwiftData detects the entitlement and tries to mirror
        // every entity through CloudKit, crashing at container init.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
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
                    }
                    await LogService.emitBoot()
                    await FileProviderManager.shared.registerDomain()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
