//
//  SkeletonLoaderView.swift
//  Rclone GUI — Views/Shared
//
//  Shimmer-animated placeholder rows used while waiting for a list payload.
//  Replaces the bland `ProgressView("Chargement…")` spinner in FolderView,
//  TrashView and TransfersView with the kind of skeleton rows users expect
//  from a premium iOS file manager.
//
//  Animation: a horizontal linear gradient that scrolls across each row,
//  highlighting the placeholder bars. Uses `phase` driven by `.repeatForever`
//  inside `withAnimation`, so the shimmer stays in sync across rows even when
//  the SwiftUI view is recomposed mid-animation.
//

import SwiftUI

/// A self-contained list-style skeleton with N rows. Caller picks the count
/// to roughly match the typical real payload (so the page doesn't reflow
/// when the data lands). Defaults to 6, suitable for a folder list above
/// the fold on iPhone.
public struct SkeletonLoaderView: View {
    public let rowCount: Int
    public let style: Style

    public enum Style {
        /// File / folder row — icon block + 2 text bars.
        case fileRow
        /// Transfer / trash row — icon + 1 wide bar + status badge.
        case transferRow
    }

    public init(rowCount: Int = 6, style: Style = .fileRow) {
        self.rowCount = rowCount
        self.style = style
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                row
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                if index != rowCount - 1 {
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Chargement en cours")
        .accessibilityHint("La liste se met à jour dans un instant.")
    }

    @ViewBuilder
    private var row: some View {
        HStack(spacing: 14) {
            ShimmerBlock()
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                ShimmerBlock()
                    .frame(maxWidth: titleWidth, alignment: .leading)
                    .frame(height: 14)
                    .clipShape(.capsule)
                ShimmerBlock()
                    .frame(maxWidth: subtitleWidth, alignment: .leading)
                    .frame(height: 11)
                    .clipShape(.capsule)
            }
            Spacer(minLength: 8)

            if style == .transferRow {
                ShimmerBlock()
                    .frame(width: 56, height: 18)
                    .clipShape(.capsule)
            }
        }
    }

    private var titleWidth: CGFloat {
        switch style {
        case .fileRow: return 220
        case .transferRow: return 260
        }
    }

    private var subtitleWidth: CGFloat {
        switch style {
        case .fileRow: return 140
        case .transferRow: return 90
        }
    }
}

/// Inner shimmer rectangle. Animates a translucent gradient sliding across
/// a base fill. The animation is bound to the system reduce-motion preference:
/// users who turn that on get a static block (still legible).
private struct ShimmerBlock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let baseColor = Color.gray.opacity(0.20)
            let highlightColor = Color.gray.opacity(0.06)

            ZStack {
                baseColor
                if !reduceMotion {
                    LinearGradient(
                        colors: [highlightColor, baseColor.opacity(0), highlightColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 1.6)
                    .offset(x: phase * width * 1.6)
                    .blendMode(.plusLighter)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
    }
}
