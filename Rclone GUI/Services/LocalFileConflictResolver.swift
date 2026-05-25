//
//  LocalFileConflictResolver.swift
//  Rclone GUI — Services
//
//  Resolves local destination conflicts for downloads.
//

import Foundation

public enum LocalConflictPolicy: String, CaseIterable, Identifiable, Sendable {
    case keepBoth
    case replace
    case skip

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .keepBoth: return "Garder les deux"
        case .replace: return "Remplacer"
        case .skip: return "Ignorer"
        }
    }
}

public enum LocalFileConflictResolver {
    public static func destination(for requestedURL: URL, policy: LocalConflictPolicy) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: requestedURL.path) else {
            return requestedURL
        }

        switch policy {
        case .skip:
            return nil
        case .replace:
            try fm.removeItem(at: requestedURL)
            return requestedURL
        case .keepBoth:
            return nextAvailableURL(for: requestedURL)
        }
    }

    private static func nextAvailableURL(for url: URL) -> URL {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var index = 2
        while true {
            let filename = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directory.appending(path: filename)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
