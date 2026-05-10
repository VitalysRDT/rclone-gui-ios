//
//  BackendCategory.swift
//  Rclone GUI — Models/Wizard
//
//  Product-friendly grouping of the 69 rclone backends. Used by the
//  add-remote wizard to render the list as collapsible sections instead
//  of a flat 69-row scroll.
//

import Foundation

enum BackendCategory: String, CaseIterable, Identifiable, Sendable, Hashable {
    case officialCloud
    case s3Compatible
    case mainstream
    case selfHosted
    case specialized
    case wrapper
    case local

    var id: String { rawValue }

    /// User-facing label (FR primary, EN fallback handled at the view layer).
    var displayName: String {
        switch self {
        case .officialCloud: return "Cloud officiels"
        case .s3Compatible:  return "S3 compatible"
        case .mainstream:    return "Sync grand public"
        case .selfHosted:    return "Self-hosted / Standards"
        case .specialized:   return "Spécialisés"
        case .wrapper:       return "Wrappers / Composites"
        case .local:         return "Local"
        }
    }

    /// Display order in the list (top = most popular).
    var displayOrder: Int {
        switch self {
        case .officialCloud: return 0
        case .s3Compatible:  return 1
        case .mainstream:    return 2
        case .selfHosted:    return 3
        case .wrapper:       return 4
        case .specialized:   return 5
        case .local:         return 6
        }
    }

    /// SF Symbol used as section header glyph.
    var icon: String {
        switch self {
        case .officialCloud: return "cloud.fill"
        case .s3Compatible:  return "cloud"
        case .mainstream:    return "person.crop.circle.fill"
        case .selfHosted:    return "server.rack"
        case .specialized:   return "puzzlepiece.fill"
        case .wrapper:       return "rectangle.stack"
        case .local:         return "internaldrive.fill"
        }
    }
}
