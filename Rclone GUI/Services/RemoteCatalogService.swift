//
//  RemoteCatalogService.swift
//  Rclone GUI — Services
//
//  Loads the rclone backend catalog by calling the embedded `config/providers`
//  RPC and merges Swift-side overrides (categories, icons, FR descriptions,
//  OAuth metadata). The result is cached in-process for the lifetime of the
//  app — schemas don't change between RPC calls because they're baked into
//  the embedded librclone.
//
//  Used by:
//  - AddRemoteWizard (NameAndBackendView, DynamicRemoteFormView)
//

import Foundation

actor RemoteCatalogService {

    // MARK: - Errors

    enum CatalogError: LocalizedError, Equatable {
        case rpcFailed(String)
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .rpcFailed(let msg):      return "Catalogue rclone indisponible : \(msg)"
            case .decodingFailed(let msg): return "Format catalogue inattendu : \(msg)"
            }
        }
    }

    // MARK: - Singleton

    static let shared = RemoteCatalogService()
    private init() {}

    // MARK: - State

    private var cached: [BackendSchema]?

    // MARK: - Public API

    /// Loads the merged catalog. First call hits the RPC; subsequent calls
    /// return the cached value. Throws `CatalogError` on failure.
    func loadCatalog() async throws -> [BackendSchema] {
        if let cached { return cached }

        let raw: String
        do {
            raw = try await RcloneCore.shared.rpcRaw("config/providers", "{}")
        } catch {
            throw CatalogError.rpcFailed(error.localizedDescription)
        }

        // Decode + merge override sont faits sur MainActor parce que
        // RcloneProvidersResponse, BackendOverrides, BackendCategory et
        // FieldSpec.init(from:) sont tous MainActor-isolés (default
        // isolation du projet). Sans ce hop, le compilateur Swift 6
        // refuse l'accès depuis l'actor RemoteCatalogService. Coût
        // négligeable : <50ms pour le decode + merge des 58 backends.
        let sorted: [BackendSchema]
        do {
            sorted = try await MainActor.run {
                let response = try JSONDecoder().decode(
                    RcloneProvidersResponse.self,
                    from: Data(raw.utf8)
                )
                let merged = response.providers.compactMap { rclone -> BackendSchema? in
                    guard !BackendOverrides.hiddenOnIOS.contains(rclone.name) else {
                        return nil
                    }
                    let category = BackendOverrides.categoryByBackend[rclone.name]
                        ?? .specialized
                    let icon = BackendOverrides.iconByBackend[rclone.name]
                        ?? "externaldrive"
                    let frDesc = BackendOverrides.frDescriptionByBackend[rclone.name]
                        ?? rclone.description
                    let oauth = BackendOverrides.oauthConfigs[rclone.name]
                    let fields = rclone.options.map { FieldSpec(from: $0) }
                    return BackendSchema(
                        name: rclone.name,
                        prefix: rclone.prefix,
                        displayName: frDesc.split(separator: "(").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? rclone.name,
                        description: frDesc,
                        category: category,
                        icon: icon,
                        fields: fields,
                        oauthConfig: oauth
                    )
                }
                return merged.sorted { lhs, rhs in
                    if lhs.category.displayOrder != rhs.category.displayOrder {
                        return lhs.category.displayOrder < rhs.category.displayOrder
                    }
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            }
        } catch let error as DecodingError {
            throw CatalogError.decodingFailed(error.localizedDescription)
        } catch {
            throw error
        }

        cached = sorted
        await LogService.shared.log(
            .info,
            category: "wizard.catalog",
            message: "Catalogue chargé : \(sorted.count) backends, \(sorted.reduce(0) { $0 + $1.fields.count }) options"
        )
        return sorted
    }

    /// Drops the in-memory cache. Call after a librclone version bump
    /// or for diagnostic / testing purposes. Rare in practice.
    func invalidate() {
        cached = nil
    }

    /// Convenience: lookup a backend by name, loading the catalog if
    /// necessary.
    func backend(named name: String) async throws -> BackendSchema? {
        let catalog = try await loadCatalog()
        return catalog.first { $0.name == name }
    }
}
