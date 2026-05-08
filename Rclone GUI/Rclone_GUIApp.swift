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
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await MainActor.run {
                        TransferQueue.shared.attach(modelContext: sharedModelContainer.mainContext)
                    }
                    await FileProviderManager.shared.registerDomain()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
