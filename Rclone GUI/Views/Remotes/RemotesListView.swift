//
//  RemotesListView.swift
//  Rclone GUI — Views/Remotes
//
//  Compatibility wrapper. The product now exposes remotes through FilesRootView.
//

import SwiftData
import SwiftUI

struct RemotesListView: View {
    var body: some View {
        FilesRootView()
    }
}

#Preview {
    NavigationStack {
        RemotesListView()
    }
    .modelContainer(
        for: [Remote.self, RemoteEntry.self, Transfer.self, TransferBatch.self, PhotoSyncAsset.self, TrashEntry.self, SavedLocation.self],
        inMemory: true
    )
}
