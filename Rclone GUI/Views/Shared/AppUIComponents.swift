//
//  AppUIComponents.swift
//  Rclone GUI — Views/Shared
//
//  Small visual primitives shared by the main SwiftUI screens.
//

import SwiftUI

enum AppSurface {
    static let cornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 14
}

extension View {
    @ViewBuilder
    func appGlassSurface(cornerRadius: CGFloat = AppSurface.cornerRadius, interactive: Bool = false) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            if interactive {
                self
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            } else {
                self
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
                .background(.thinMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.quaternary)
                }
        }
        #else
        self
            .background(.thinMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.quaternary)
            }
        #endif
    }
}

struct AppIconTile: View {
    let systemImage: String
    var tint: Color = .accentColor
    var size: CGFloat = 44
    var iconSize: Font = .title3
    var filled = false

    var body: some View {
        Image(systemName: systemImage)
            .font(iconSize.weight(.semibold))
            .foregroundStyle(filled ? .white : tint)
            .frame(width: size, height: size)
            .background(filled ? tint : tint.opacity(0.14), in: .rect(cornerRadius: min(14, size / 3), style: .continuous))
            .accessibilityHidden(true)
    }
}

struct AppStatusBadge: View {
    let title: String
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

struct AppSectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var systemImage: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
        }
        .textCase(nil)
    }
}

struct AppMetricPill: View {
    let value: String
    let label: LocalizedStringKey
    var systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .appGlassSurface(cornerRadius: 11)
    }
}

struct AppMetricTile: View {
    let value: String
    let label: LocalizedStringKey
    var systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AppIconTile(systemImage: systemImage, tint: tint, size: 34, iconSize: .callout)
                Spacer(minLength: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassSurface(cornerRadius: AppSurface.compactCornerRadius)
        .accessibilityElement(children: .combine)
    }
}

struct AppActionTile: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            AppIconTile(systemImage: systemImage, tint: tint, size: 42, iconSize: .body, filled: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassSurface(cornerRadius: AppSurface.compactCornerRadius, interactive: true)
        .accessibilityElement(children: .combine)
    }
}

struct AppHeroCard<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                AppIconTile(systemImage: systemImage, tint: tint, size: 58, iconSize: .title2, filled: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassSurface(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}

struct AppLocationRow: View {
    let title: String
    let subtitle: String
    var systemImage: String = "folder.fill"
    var tint: Color = .blue
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            AppIconTile(systemImage: systemImage, tint: tint, size: 40, iconSize: .body)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct AppInlineMessage: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .appGlassSurface(cornerRadius: AppSurface.compactCornerRadius)
        .accessibilityElement(children: .combine)
    }
}

struct AppEmptyStateView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 12) {
            AppIconTile(systemImage: systemImage, tint: tint, size: 58, iconSize: .title2)
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .appGlassSurface(cornerRadius: AppSurface.cornerRadius)
        .accessibilityElement(children: .combine)
    }
}

struct AppFloatingActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(10)
        .appGlassSurface(cornerRadius: 22, interactive: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - Toast (C3 : remplace les `.alert` bloquants)

/// Severity-typed toast model. Passe-le à `.appToast(_:)` via un binding
/// optionnel — `nil` cache la bannière, non-nil l'affiche.
struct AppToast: Equatable, Identifiable {
    enum Severity {
        case info, success, warning, error
    }

    let id = UUID()
    let title: String
    let message: String?
    let severity: Severity

    init(title: String, message: String? = nil, severity: Severity = .info) {
        self.title = title
        self.message = message
        self.severity = severity
    }
}

struct AppToastBanner: View {
    let toast: AppToast
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(toast.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let msg = toast.message, !msg.isEmpty {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(.tertiary.opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer le toast")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassSurface(cornerRadius: AppSurface.cornerRadius)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(toast.title)\(toast.message.map { ". \($0)" } ?? "")")
    }

    private var iconName: String {
        switch toast.severity {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch toast.severity {
        case .info:    return .blue
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

extension View {
    /// Affiche un toast non-bloquant en bas de l'écran. Auto-dismiss en
    /// 3s (info/success), 5s (warning), 7s (error). Tap sur la croix
    /// pour fermer manuellement. Remplace les `.alert(...)` bloquants
    /// utilisés pour signaler les actions PhotoSync (pause, retry…).
    func appToast(_ binding: Binding<AppToast?>) -> some View {
        modifier(AppToastModifier(toast: binding))
    }
}

private struct AppToastModifier: ViewModifier {
    @Binding var toast: AppToast?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let current = toast {
                    AppToastBanner(toast: current) {
                        dismissTask?.cancel()
                        withAnimation(.easeOut(duration: 0.2)) {
                            toast = nil
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.18), value: toast)
            .onChange(of: toast) { _, newValue in
                dismissTask?.cancel()
                guard let newValue else { return }
                let lifetime: TimeInterval
                switch newValue.severity {
                case .info, .success: lifetime = 3
                case .warning:        lifetime = 5
                case .error:          lifetime = 7
                }
                dismissTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(lifetime))
                    if Task.isCancelled { return }
                    // Vérifie qu'aucun nouveau toast n'a remplacé celui-ci.
                    if toast?.id == newValue.id {
                        withAnimation(.easeOut(duration: 0.25)) {
                            toast = nil
                        }
                    }
                }
            }
    }
}
