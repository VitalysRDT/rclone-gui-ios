//
//  PlatformModifiers.swift
//  Rclone GUI — Views/Shared
//
//  Cross-platform shims for iOS-only SwiftUI view modifiers. Keeps call sites
//  free of #if os(iOS) noise: on iOS they apply the native modifier, on macOS
//  (and other platforms) they are no-ops. Same spirit as the Color helpers in
//  DesignSystem.swift.
//

import SwiftUI

extension View {
    /// `navigationBarTitleDisplayMode(.inline)` on iOS, no-op elsewhere.
    /// macOS navigation titles are inline by default.
    @ViewBuilder
    func rgInlineNavTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// `textInputAutocapitalization(.never)` on iOS, no-op elsewhere.
    /// macOS text fields have no autocapitalization concept.
    @ViewBuilder
    func rgNoAutocap() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// `.insetGrouped` list style on iOS (unavailable on macOS); `.inset` on
    /// macOS, which is the closest sidebar-friendly grouped look.
    @ViewBuilder
    func rgInsetGroupedList() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    /// `fullScreenCover(item:)` on iOS (unavailable on macOS); falls back to a
    /// `sheet(item:)` on macOS, where modal windows are the native equivalent.
    @ViewBuilder
    func rgFullScreenCover<Item: Identifiable, ItemContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> ItemContent
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #else
        self.sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}
