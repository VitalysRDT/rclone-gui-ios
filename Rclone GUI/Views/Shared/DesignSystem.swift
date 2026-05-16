//
//  DesignSystem.swift
//  Rclone GUI — Views/Shared
//
//  Visual tokens and primitives derived from the
//  "Rclone GUI iOS — Walkthrough" design handoff.
//  Defines accent (#7C3AED), backend chip palette, crypt-forward badges,
//  file-state glyphs, gradient seals, action tiles. Used across all screens
//  to keep the crypt-first identity coherent.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Platform helpers

extension Color {
    /// Cross-platform replacement for `Color(.systemBackground)`.
    static var rgSystemBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Cross-platform replacement for `Color(.secondarySystemGroupedBackground)`,
    /// the colour used by `.insetGrouped` rows.
    static var rgGroupedRowBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

// MARK: - Tokens

enum RG {
    /// Primary purple accent. Resolved from the asset catalog so iOS picks the
    /// dark-mode variant automatically (lighter violet for WCAG AA ≥4.5:1).
    static let accent = Color("AccentColor")
    /// 18% accent fill used for soft pills, badges, icon tiles.
    /// Slightly stronger than the original 14% to preserve legibility in dark mode.
    static let accentSoft = Color("AccentColor").opacity(0.18)
    /// Deeper end of the seal gradient (used in light mode only).
    static let accentDeep = Color(red: 91 / 255, green: 33 / 255, blue: 182 / 255)

    /// Brand monospaced font (file paths, hashes, technical chips).
    static let mono: Font = .system(.caption, design: .monospaced)

    enum Radius {
        static let card: CGFloat = 14
        static let group: CGFloat = 12
        static let chip: CGFloat = 10
        static let pill: CGFloat = 999
    }
}

// MARK: - Backend palette

/// Mapping rclone backend → brand color + glyph, mirroring the design's
/// `BackendIcon` chips. Falls back to a neutral grey for unknown types.
enum RGBackend: Hashable, Sendable {
    case s3, b2, sftp, ftp, webdav, drive, dropbox, onedrive, box
    case crypt, local, mega, pcloud, generic

    static func from(rcloneType: String) -> RGBackend {
        switch rcloneType.lowercased() {
        case "s3":                      return .s3
        case "b2":                      return .b2
        case "sftp":                    return .sftp
        case "ftp":                     return .ftp
        case "webdav":                  return .webdav
        case "drive", "googlephotos":   return .drive
        case "dropbox":                 return .dropbox
        case "onedrive":                return .onedrive
        case "box":                     return .box
        case "crypt":                   return .crypt
        case "local", "alias":          return .local
        case "mega":                    return .mega
        case "pcloud":                  return .pcloud
        default:                        return .generic
        }
    }

    var color: Color {
        switch self {
        case .s3:        return Color(red: 1.0, green: 0.584, blue: 0.0)        // S3 / R2 / Bunny family
        case .b2:        return Color(red: 0.898, green: 0.224, blue: 0.208)
        case .sftp:      return Color(red: 0.204, green: 0.78, blue: 0.349)
        case .ftp:       return Color(red: 0.0, green: 0.5, blue: 0.6)
        case .webdav:    return Color(red: 0.345, green: 0.337, blue: 0.839)
        case .drive:     return Color(red: 0.102, green: 0.451, blue: 0.91)
        case .dropbox:   return Color(red: 0.0, green: 0.38, blue: 1.0)
        case .onedrive:  return Color(red: 0.012, green: 0.392, blue: 0.722)
        case .box:       return Color(red: 0.0, green: 0.38, blue: 0.835)
        case .crypt:     return RG.accent
        case .local:     return Color(red: 0.557, green: 0.557, blue: 0.576)
        case .mega:      return Color(red: 0.851, green: 0.153, blue: 0.18)
        case .pcloud:    return Color(red: 0.086, green: 0.627, blue: 0.522)
        case .generic:   return Color.secondary
        }
    }

    var systemImage: String {
        switch self {
        case .crypt:    return "lock.fill"
        case .sftp,
             .ftp:      return "server.rack"
        case .webdav:   return "globe"
        case .local:    return "folder.fill"
        default:        return "cloud.fill"
        }
    }

    /// Short uppercase label (e.g. "S3", "DAV", "Crypt"). Not currently
    /// rendered, but reserved for tooltip / accessibility.
    var shortLabel: String {
        switch self {
        case .s3:       return "S3"
        case .b2:       return "B2"
        case .sftp:     return "SFTP"
        case .ftp:      return "FTP"
        case .webdav:   return "DAV"
        case .drive:    return "Drive"
        case .dropbox:  return "Dropbox"
        case .onedrive: return "OneDrive"
        case .box:      return "Box"
        case .crypt:    return "Crypt"
        case .local:    return "Local"
        case .mega:     return "Mega"
        case .pcloud:   return "pCloud"
        case .generic:  return "?"
        }
    }
}

// MARK: - BackendChip

/// Colored rounded square holding a glyph — the design's signature element
/// for marking which backend a remote belongs to.
struct BackendChip: View {
    let backend: RGBackend
    /// When true, overlays a small purple lock badge in the bottom-right —
    /// used when a non-crypt backend is wrapped in a crypt remote.
    var cryptOverlay: Bool = false
    var size: CGFloat = 36

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(backend.color)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: backend.systemImage)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
                .shadow(color: backend.color.opacity(0.18), radius: 4, x: 0, y: 2)

            if cryptOverlay {
                Circle()
                    .fill(RG.accent)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .overlay {
                        Image(systemName: "lock.fill")
                            .font(.system(size: size * 0.22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .overlay {
                        Circle().stroke(Color.rgSystemBackground, lineWidth: 2)
                    }
                    .offset(x: size * 0.06, y: size * 0.06)
            }
        }
        .frame(width: size + (cryptOverlay ? 4 : 0), height: size + (cryptOverlay ? 4 : 0), alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// MARK: - Crypt badge

/// Inline pill that says "CRYPT" — used inside titles to emphasize when
/// a remote or path is end-to-end encrypted.
struct CryptBadge: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
                .font(.system(size: compact ? 8 : 9, weight: .bold))
            Text("CRYPT")
                .font(.system(size: compact ? 9 : 10, weight: .bold))
                .tracking(0.4)
        }
        .foregroundStyle(RG.accent)
        .padding(.horizontal, compact ? 4 : 5)
        .padding(.vertical, compact ? 1 : 2)
        .background(RG.accentSoft, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityLabel("Chiffré")
    }
}

// MARK: - File state glyph

/// Mirrors the design's per-row "where is this file?" indicator —
/// cloud (remote), local (downloaded), syncing (in progress), or
/// downloading with a progress arc.
enum RGFileState: Equatable {
    case cloud
    case local
    case syncing
    case downloading(progress: Double)
}

struct FileStateGlyph: View {
    let state: RGFileState

    var body: some View {
        switch state {
        case .cloud:
            Image(systemName: "cloud")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Sur le remote")
        case .local:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.green)
                .accessibilityLabel("Téléchargé localement")
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .accessibilityLabel("Synchronisation en cours")
        case .downloading(let progress):
            ProgressArc(progress: max(0, min(1, progress)))
                .frame(width: 18, height: 18)
                .accessibilityLabel("Téléchargement \(Int(progress * 100)) pour cent")
        }
    }
}

private struct ProgressArc: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(RG.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Action tile (4-column grid on file detail)

/// Single tile inside the file-detail action grid. The first tile is
/// rendered as `primary = true` (filled accent) to mirror the iOS Files
/// "Open" button hierarchy.
struct RGActionTile: View {
    let title: String
    let systemImage: String
    var primary: Bool = false
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(primary ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(primary ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(primary ? AnyShapeStyle(RG.accent) : AnyShapeStyle(.thinMaterial),
                        in: RoundedRectangle(cornerRadius: RG.Radius.group, style: .continuous))
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: RG.Radius.group, style: .continuous)
                        .stroke(.quaternary, lineWidth: 0.5)
                }
            }
            .shadow(color: primary ? RG.accent.opacity(0.25) : .clear, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hero crypt seal

/// Big purple gradient lock with a green checkmark badge — the
/// onboarding hero element in the design. ~120pt by default.
struct RGCryptSeal: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [RG.accent, RG.accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                        .padding(0.5)
                }
                .shadow(color: RG.accent.opacity(0.35), radius: 18, x: 0, y: 14)

            Circle()
                .fill(.green)
                .frame(width: size * 0.27, height: size * 0.27)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.13, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle().stroke(Color.rgSystemBackground, lineWidth: 3)
                }
                .offset(x: size * 0.04, y: -size * 0.04)
        }
        .frame(width: size + 6, height: size + 6, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// MARK: - Gradient avatar

/// Initials avatar with the accent gradient — used in the Settings
/// account card. Initials are derived from the supplied name.
struct RGGradientAvatar: View {
    let name: String
    var size: CGFloat = 48

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [RG.accent, RG.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(name)
    }

    private var initials: String {
        let parts = name
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { $0.first.map(String.init) }
        return parts.prefix(2).joined().uppercased()
    }
}

// MARK: - Inline section card

/// `card`-style group used by the design — a solid-background rectangle with
/// a small radius. Sits between native `.insetGrouped` (heavy chrome) and
/// `appGlassSurface` (liquid-glass material). Use for ad-hoc cards that
/// need a clean inset look on top of a grouped background.
struct RGSolidCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Color.rgGroupedRowBackground,
                        in: RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous))
    }
}

// MARK: - Section pill heading (uppercase 13pt)

/// Small uppercase label used by the design's `ListGroup` headers.
/// Pairs nicely with `RGSolidCard`.
struct RGGroupHeader: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .regular))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
