//
//  PhotoSyncAlbumPicker.swift
//  Rclone GUI — Views/Settings
//
//  Multi-select picker for PHAssetCollection. Persists the chosen album
//  identifiers as a JSON-encoded array of strings in UserDefaults under
//  PhotoSyncAlbumStore.userDefaultsKey, so PhotoSyncService can filter the
//  candidate scan accordingly.
//
//  An empty selection means "every visible photo" (current default behavior).
//

#if os(iOS)
import Photos
import SwiftUI

struct PhotoSyncAlbumPicker: View {
    @State private var smartAlbums: [AlbumEntry] = []
    @State private var userAlbums: [AlbumEntry] = []
    @State private var selectedIDs: Set<String> = PhotoSyncAlbumStore.load()
    @State private var isLoading = true
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined

    struct AlbumEntry: Identifiable, Hashable {
        let id: String
        let title: String
        let assetCount: Int
        let symbolName: String
    }

    var body: some View {
        Group {
            switch authorizationStatus {
            case .denied, .restricted:
                ContentUnavailableView(
                    "Accès Photos refusé",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("Activez l'accès à la photothèque dans Réglages › Confidentialité.")
                )
            default:
                if isLoading {
                    ProgressView("Chargement des albums…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if smartAlbums.isEmpty && userAlbums.isEmpty {
                    ContentUnavailableView(
                        "Aucun album",
                        systemImage: "rectangle.stack",
                        description: Text("La photothèque ne contient aucun album exploitable.")
                    )
                } else {
                    list
                }
            }
        }
        .navigationTitle("Albums à sauvegarder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        selectedIDs.removeAll()
                        save()
                    } label: {
                        Label("Tout désélectionner (sauvegarder tout)", systemImage: "checkmark.circle")
                    }
                    .disabled(selectedIDs.isEmpty)
                    Button {
                        selectedIDs = Set(smartAlbums.map(\.id) + userAlbums.map(\.id))
                        save()
                    } label: {
                        Label("Tout sélectionner", systemImage: "square.stack.3d.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await reload()
        }
    }

    @ViewBuilder
    private var list: some View {
        List {
            Section {
                summaryRow
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if !smartAlbums.isEmpty {
                Section {
                    ForEach(smartAlbums) { album in
                        row(for: album)
                    }
                } header: {
                    Text("Albums système")
                }
            }
            if !userAlbums.isEmpty {
                Section {
                    ForEach(userAlbums) { album in
                        row(for: album)
                    }
                } header: {
                    Text("Mes albums")
                }
            }
        }
    }

    @ViewBuilder
    private var summaryRow: some View {
        HStack(spacing: 14) {
            Image(systemName: selectedIDs.isEmpty ? "infinity" : "checkmark.rectangle.stack")
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(.white)
                .background(selectedIDs.isEmpty ? Color.gray : Color.pink, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedIDs.isEmpty ? "Tous les albums" : "\(selectedIDs.count) album(s) sélectionné(s)")
                    .font(.headline)
                Text(selectedIDs.isEmpty
                     ? "Toutes les photos visibles seront sauvegardées."
                     : "Seules les photos de ces albums seront sauvegardées.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary)
        }
    }

    @ViewBuilder
    private func row(for album: AlbumEntry) -> some View {
        Button {
            toggle(album.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: album.symbolName)
                    .frame(width: 28)
                    .font(.body)
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(album.assetCount) élément\(album.assetCount > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: selectedIDs.contains(album.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedIDs.contains(album.id) ? Color.blue : Color.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        save()
    }

    private func save() {
        PhotoSyncAlbumStore.save(selectedIDs)
    }

    @MainActor
    private func reload() async {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            isLoading = false
            return
        }

        async let smart = Self.fetchAlbums(.smartAlbum)
        async let user = Self.fetchAlbums(.album)
        smartAlbums = await smart
        userAlbums = await user
        isLoading = false
    }

    private static func fetchAlbums(_ type: PHAssetCollectionType) async -> [AlbumEntry] {
        await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            let collections = PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: options)
            var result: [AlbumEntry] = []
            collections.enumerateObjects { collection, _, _ in
                let title = collection.localizedTitle ?? "Sans titre"
                let assetOptions = PHFetchOptions()
                assetOptions.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
                let count = PHAsset.fetchAssets(in: collection, options: assetOptions).count
                guard count > 0 else { return }  // skip empty collections
                let symbol = symbolName(for: collection.assetCollectionSubtype, type: type)
                result.append(AlbumEntry(id: collection.localIdentifier, title: title, assetCount: count, symbolName: symbol))
            }
            return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }.value
    }

    private static func symbolName(for subtype: PHAssetCollectionSubtype, type: PHAssetCollectionType) -> String {
        if type == .album { return "rectangle.stack" }
        switch subtype {
        case .smartAlbumFavorites: return "heart"
        case .smartAlbumVideos: return "video"
        case .smartAlbumScreenshots: return "iphone"
        case .smartAlbumSelfPortraits: return "person.crop.square"
        case .smartAlbumPanoramas: return "pano"
        case .smartAlbumSlomoVideos: return "slowmo"
        case .smartAlbumTimelapses: return "timelapse"
        case .smartAlbumBursts: return "rectangle.stack.fill"
        case .smartAlbumLivePhotos: return "livephoto"
        case .smartAlbumDepthEffect: return "f.cursive"
        case .smartAlbumAnimated: return "figure.walk.motion"
        default: return "photo.on.rectangle"
        }
    }
}

/// Persistence layer for the album multi-select. We can't use @AppStorage
/// directly because Set<String> isn't supported, and serializing to a JSON
/// string handles the union semantics PhotoSyncService needs to query at
/// scan time.
///
/// Both methods are explicitly `nonisolated` so they can be called from the
/// `nonisolated` PhotoSyncService.scanPhotoLibrary context without Swift 6's
/// MainActor inheritance complaining. UserDefaults read/write is documented
/// as thread-safe for individual accesses; a stale-read window between save
/// and a concurrent in-flight scan is acceptable (and bounded by the next
/// scan cycle).
nonisolated public enum PhotoSyncAlbumStore {
    public static let userDefaultsKey = "photosync.selectedAlbumIDs"

    nonisolated public static func load() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    nonisolated public static func save(_ ids: Set<String>) {
        let array = Array(ids).sorted()
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
#endif
