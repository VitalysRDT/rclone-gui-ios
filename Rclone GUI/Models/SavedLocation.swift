//
//  SavedLocation.swift
//  Rclone GUI — Models
//
//  Local navigation shortcuts for pinned folders and recent locations.
//

import Foundation
import SwiftData

public enum SavedLocationKind: String, Codable, Sendable, CaseIterable {
    case recent
    case pinned
}

@Model
public final class SavedLocation {
    @Attribute(.unique) public var id: String
    public var kindRaw: String
    public var remote: String
    public var path: String
    public var displayName: String
    public var createdAt: Date
    public var lastOpenedAt: Date
    public var openCount: Int
    public var sortIndex: Int

    public var kind: SavedLocationKind {
        get { SavedLocationKind(rawValue: kindRaw) ?? .recent }
        set {
            kindRaw = newValue.rawValue
            id = Self.makeID(kind: newValue, remote: remote, path: path)
        }
    }

    public init(
        kind: SavedLocationKind,
        remote: String,
        path: String,
        displayName: String,
        createdAt: Date = .now,
        lastOpenedAt: Date = .now,
        openCount: Int = 0,
        sortIndex: Int = 0
    ) {
        self.id = Self.makeID(kind: kind, remote: remote, path: path)
        self.kindRaw = kind.rawValue
        self.remote = remote
        self.path = Self.clean(path)
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.openCount = openCount
        self.sortIndex = sortIndex
    }

    public static func makeID(kind: SavedLocationKind, remote: String, path: String) -> String {
        "\(kind.rawValue)|\(remote)|\(clean(path))"
    }

    public static func clean(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

extension SavedLocation {
    public var destination: NavigationDestination {
        .folder(remote: remote, path: path)
    }

    public var subtitle: String {
        path.isEmpty ? "\(remote):/" : "\(remote):\(path)"
    }
}
