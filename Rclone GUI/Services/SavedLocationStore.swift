//
//  SavedLocationStore.swift
//  Rclone GUI — Services
//
//  Small SwiftData helper for recent and pinned remote folders.
//

import Foundation
import SwiftData

public enum SavedLocationStore {
    public static let recentLimit = 12

    @MainActor
    @discardableResult
    public static func recordOpen(
        remote: String,
        path: String,
        displayName: String,
        in context: ModelContext
    ) throws -> SavedLocation {
        let cleanPath = SavedLocation.clean(path)
        let id = SavedLocation.makeID(kind: .recent, remote: remote, path: cleanPath)
        let now = Date()

        if let existing = try fetch(id: id, in: context) {
            existing.displayName = displayName
            existing.lastOpenedAt = now
            existing.openCount += 1
            try context.save()
            try pruneRecents(limit: recentLimit, in: context)
            return existing
        }

        let location = SavedLocation(
            kind: .recent,
            remote: remote,
            path: cleanPath,
            displayName: displayName,
            createdAt: now,
            lastOpenedAt: now,
            openCount: 1
        )
        context.insert(location)
        try context.save()
        try pruneRecents(limit: recentLimit, in: context)
        return location
    }

    @MainActor
    public static func isPinned(remote: String, path: String, in context: ModelContext) throws -> Bool {
        let id = SavedLocation.makeID(kind: .pinned, remote: remote, path: path)
        return try fetch(id: id, in: context) != nil
    }

    @MainActor
    @discardableResult
    public static func togglePinned(
        remote: String,
        path: String,
        displayName: String,
        in context: ModelContext
    ) throws -> Bool {
        let cleanPath = SavedLocation.clean(path)
        let id = SavedLocation.makeID(kind: .pinned, remote: remote, path: cleanPath)
        if let existing = try fetch(id: id, in: context) {
            context.delete(existing)
            try context.save()
            return false
        }

        let pinned = SavedLocation(
            kind: .pinned,
            remote: remote,
            path: cleanPath,
            displayName: displayName,
            openCount: 0,
            sortIndex: nextPinnedSortIndex(in: context)
        )
        context.insert(pinned)
        try context.save()
        return true
    }

    @MainActor
    public static func pruneRecents(limit: Int, in context: ModelContext) throws {
        guard limit >= 0 else { return }
        // #Predicate ne peut pas expand .rawValue d'une enum case directement
        // (key path expansion error) — on extrait la valeur dans un let.
        let recentRaw = SavedLocationKind.recent.rawValue
        let descriptor = FetchDescriptor<SavedLocation>(
            predicate: #Predicate { $0.kindRaw == recentRaw },
            sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
        )
        let recents = try context.fetch(descriptor)
        guard recents.count > limit else { return }
        for location in recents.dropFirst(limit) {
            context.delete(location)
        }
        try context.save()
    }

    @MainActor
    public static func removeUnavailableRemotes(_ availableRemotes: Set<String>, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<SavedLocation>()
        let all = try context.fetch(descriptor)
        for location in all where !availableRemotes.contains(location.remote) {
            context.delete(location)
        }
        try context.save()
    }

    /// Supprime tous les favoris et récents (utilisé après un wipe complet).
    @MainActor
    public static func removeAll(in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<SavedLocation>())
        guard !all.isEmpty else { return }
        for location in all {
            context.delete(location)
        }
        try context.save()
    }

    /// Supprime tous les emplacements (favoris + récents) liés à un remote
    /// donné (utilisé après suppression de ce remote).
    @MainActor
    public static func removeForRemote(_ remote: String, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<SavedLocation>(
            predicate: #Predicate { $0.remote == remote }
        )
        let matches = try context.fetch(descriptor)
        guard !matches.isEmpty else { return }
        for location in matches {
            context.delete(location)
        }
        try context.save()
    }

    @MainActor
    public static func locations(kind: SavedLocationKind, in context: ModelContext) throws -> [SavedLocation] {
        // Idem : on capture rawValue dans un let pour que #Predicate puisse
        // l'inliner comme une simple String.
        let raw = kind.rawValue
        switch kind {
        case .recent:
            let descriptor = FetchDescriptor<SavedLocation>(
                predicate: #Predicate { $0.kindRaw == raw },
                sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
            )
            return try context.fetch(descriptor)
        case .pinned:
            let descriptor = FetchDescriptor<SavedLocation>(
                predicate: #Predicate { $0.kindRaw == raw },
                sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]
            )
            return try context.fetch(descriptor)
        }
    }

    @MainActor
    private static func fetch(id: String, in context: ModelContext) throws -> SavedLocation? {
        var descriptor = FetchDescriptor<SavedLocation>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @MainActor
    private static func nextPinnedSortIndex(in context: ModelContext) -> Int {
        let pinnedRaw = SavedLocationKind.pinned.rawValue
        let descriptor = FetchDescriptor<SavedLocation>(
            predicate: #Predicate { $0.kindRaw == pinnedRaw },
            sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
        )
        let maxIndex = (try? context.fetch(descriptor).first?.sortIndex) ?? 0
        return maxIndex + 1
    }
}
