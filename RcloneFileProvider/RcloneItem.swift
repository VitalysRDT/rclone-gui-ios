//
//  RcloneItem.swift
//  Rclone GUI — FileProvider Extension
//
//  NSFileProviderItem implementation. Identifier scheme:
//
//      "<remote>:<path>"        → file or folder
//      ""                       → root (lists all remotes as virtual folders)
//      ".rclone-trash"          → working set / trash placeholder (P1)
//

import Foundation
import FileProvider
import UniformTypeIdentifiers

public final class RcloneItem: NSObject, NSFileProviderItem {

    public let id: NSFileProviderItemIdentifier
    public let parentID: NSFileProviderItemIdentifier
    public let displayName: String
    public let isDirectory: Bool
    public let size: Int64
    public let modTime: Date

    public init(
        id: NSFileProviderItemIdentifier,
        parentID: NSFileProviderItemIdentifier,
        displayName: String,
        isDirectory: Bool,
        size: Int64,
        modTime: Date
    ) {
        self.id = id
        self.parentID = parentID
        self.displayName = displayName
        self.isDirectory = isDirectory
        self.size = size
        self.modTime = modTime
        super.init()
    }

    // MARK: - NSFileProviderItem

    public var itemIdentifier: NSFileProviderItemIdentifier { id }
    public var parentItemIdentifier: NSFileProviderItemIdentifier { parentID }
    public var filename: String { displayName }
    public var documentSize: NSNumber? { isDirectory ? nil : NSNumber(value: size) }
    public var creationDate: Date? { modTime }
    public var contentModificationDate: Date? { modTime }

    public var contentType: UTType {
        if isDirectory { return .folder }
        let ext = (displayName as NSString).pathExtension
        return UTType(filenameExtension: ext) ?? .data
    }

    public var capabilities: NSFileProviderItemCapabilities {
        if isDirectory {
            return [.allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming, .allowsDeleting, .allowsReparenting]
        }
        return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting, .allowsReparenting]
    }

    // MARK: - Identifier helpers

    public static let rootIdentifier = NSFileProviderItemIdentifier.rootContainer

    public static func identifier(remote: String, path: String) -> NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier("\(remote):\(path)")
    }

    public static func decode(_ identifier: NSFileProviderItemIdentifier) -> (remote: String, path: String)? {
        let raw = identifier.rawValue
        guard let colonIndex = raw.firstIndex(of: ":") else { return nil }
        let remote = String(raw[..<colonIndex])
        let path = String(raw[raw.index(after: colonIndex)...])
        return (remote, path)
    }
}
