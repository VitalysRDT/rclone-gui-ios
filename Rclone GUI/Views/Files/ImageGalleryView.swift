//
//  ImageGalleryView.swift
//  Rclone GUI — Views/Files
//
//  Visionneuse photo plein écran : swipe entre images (TabView paginé sur iOS,
//  flèches + clavier sur macOS), pinch-zoom + pan, double-tap, partage /
//  enregistrement. Réutilise le bridge loopback (RcloneStreamingService) pour
//  charger une image *downsamplée* — mémoire bornée via ImageIO quel que soit
//  le poids source — et MediaCacheService pour partager le fichier original.
//

import SwiftUI
import CoreGraphics
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Contexte de présentation

/// La liste d'images du dossier + l'index de départ. `Identifiable` pour piloter
/// `rgFullScreenCover(item:)` depuis FolderView.
struct ImageGalleryContext: Identifiable {
    let id = UUID()
    let remote: String
    /// Images uniquement, dans l'ordre affiché du dossier.
    let entries: [RemoteEntryDTO]
    let startIndex: Int
}

// MARK: - Chargeur d'image bornée

/// Charge une image distante *downsamplée* via le bridge loopback. Le
/// downsampling ImageIO décode directement à la taille cible → la RAM est
/// bornée même pour un original de 100 Mo (RAW/TIFF).
enum GalleryImageLoader {
    /// Plafond du plus grand côté à l'affichage (~2400 px ≈ 23 Mo décodés).
    /// Suffit pour tous les écrans iPhone/iPad et borne la mémoire du carrousel.
    nonisolated static let displayMaxPixel: Int = 2400
    /// Au-delà, on n'essaie même pas de télécharger l'original (anti-OOM).
    nonisolated static let sourceSizeCap: Int64 = 200 * 1024 * 1024

    /// `nonisolated` : le téléchargement + ImageIO tournent hors du main actor
    /// (le projet est en isolation main-actor par défaut, cf. ThumbnailService).
    nonisolated static func loadDownsampled(
        remote: String,
        entry: RemoteEntryDTO,
        maxPixel: Int = displayMaxPixel
    ) async -> CGImage? {
        if entry.size > 0, entry.size > sourceSizeCap { return nil }
        guard let session = await RcloneStreamingService.shared.liveSession(
            remote: remote, path: entry.pathInRemote
        ) else { return nil }
        defer { Task { await RcloneStreamingService.shared.stop(session) } }

        guard let (data, _) = try? await URLSession.shared.data(from: session.url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // applique l'orientation EXIF directement dans le bitmap décodé
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

// MARK: - Vue principale

struct ImageGalleryView: View {
    let context: ImageGalleryContext
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    @State private var showChrome = true
    @State private var shareURL: URL?
    @State private var isPreparingShare = false
    @State private var shareError: String?
    #if os(iOS)
    @State private var showingShare = false
    #endif

    init(context: ImageGalleryContext) {
        self.context = context
        _index = State(initialValue: context.startIndex)
    }

    private var entries: [RemoteEntryDTO] { context.entries }
    private var current: RemoteEntryDTO? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            pager
            if showChrome { chrome.transition(.opacity) }
        }
        #if os(iOS)
        .statusBarHidden(!showChrome)
        .sheet(isPresented: $showingShare) {
            if let shareURL { GalleryShareSheet(items: [shareURL]) }
        }
        #endif
        .alert("Partage impossible", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "")
        }
    }

    // MARK: Pager

    #if os(iOS)
    private var pager: some View {
        TabView(selection: $index) {
            ForEach(Array(entries.enumerated()), id: \.offset) { offset, entry in
                ZoomableRemoteImage(
                    remote: context.remote,
                    entry: entry,
                    onToggleChrome: toggleChrome
                )
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
    #else
    private var pager: some View {
        ZoomableRemoteImage(
            remote: context.remote,
            entry: current ?? entries[0],
            onToggleChrome: toggleChrome
        )
        .id(index)
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { goPrev(); return .handled }
        .onKeyPress(.rightArrow) { goNext(); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }
    #endif

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                circleButton(system: "xmark") { dismiss() }
                Spacer()
                Text("\(index + 1) / \(entries.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                shareButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            bottomBar
        }
    }

    private var shareButton: some View {
        Button(action: shareCurrent) {
            Group {
                if isPreparingShare {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 38, height: 38)
            .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(current == nil || isPreparingShare)
        .accessibilityLabel("Partager ou enregistrer")
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            #if os(macOS)
            HStack(spacing: 24) {
                circleButton(system: "chevron.left") { goPrev() }
                    .disabled(index <= 0)
                circleButton(system: "chevron.right") { goNext() }
                    .disabled(index >= entries.count - 1)
            }
            #endif
            if let name = current?.name {
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.bottom, 24)
    }

    private func circleButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: Actions

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
    }

    private func goPrev() {
        guard index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { index -= 1 }
    }

    private func goNext() {
        guard index < entries.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
    }

    private func shareCurrent() {
        guard let entry = current, !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            do {
                let url = try await MediaCacheService.shared.localPlayableURL(
                    remote: context.remote,
                    path: entry.pathInRemote,
                    sizeHint: entry.size,
                    policy: .reuseIfCached
                )
                shareURL = url
                #if os(iOS)
                showingShare = true
                #elseif canImport(AppKit)
                presentMacSave(url, suggestedName: entry.name)
                #endif
            } catch {
                shareError = error.localizedDescription
            }
        }
    }

    #if canImport(AppKit)
    private func presentMacSave(_ url: URL, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
    }
    #endif
}

// MARK: - Image zoomable

private struct ZoomableRemoteImage: View {
    let remote: String
    let entry: RemoteEntryDTO
    let onToggleChrome: () -> Void

    @State private var image: CGImage?
    @State private var loadFailed = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let maxScale: CGFloat = 5
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                content(in: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
        }
        .task(id: entry.id) { await load() }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let image {
            platformImage(image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: size.width, height: size.height)
                .modifier(PanWhenZoomed(enabled: scale > 1.01, offset: $offset, lastOffset: $lastOffset))
                .gesture(magnification)
                .onTapGesture(count: 2) { toggleZoom() }
                .onTapGesture(count: 1) { onToggleChrome() }
        } else if loadFailed {
            failedState
        } else {
            ProgressView().controlSize(.large).tint(.white)
        }
    }

    private var failedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.7))
            Text("Image illisible")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
        }
        .onTapGesture { onToggleChrome() }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 { resetZoom() }
            }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.25)) {
            if scale > 1.01 {
                resetZoom()
            } else {
                scale = doubleTapScale
                lastScale = doubleTapScale
            }
        }
    }

    private func resetZoom() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }

    private func load() async {
        image = nil
        loadFailed = false
        resetZoom()
        // Placeholder instantané : vignette 400px (souvent déjà en cache).
        if let thumb = await ThumbnailService.shared.thumbnail(for: entry, remote: remote),
           image == nil {
            image = thumb.image
        }
        // Hi-res downsamplé borné.
        if let hi = await GalleryImageLoader.loadDownsampled(remote: remote, entry: entry) {
            image = hi
        } else if image == nil {
            loadFailed = true
        }
    }

    private func platformImage(_ cg: CGImage) -> Image {
        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cg))
        #elseif canImport(AppKit)
        return Image(nsImage: NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height)))
        #else
        return Image(systemName: "photo")
        #endif
    }
}

/// Le pan n'est attaché QUE lorsque l'image est zoomée : sinon, à l'échelle 1,
/// le `DragGesture` capterait le swipe horizontal et bloquerait la pagination
/// du TabView. En `highPriorityGesture`, il prend le pas sur le scroll quand on
/// est zoomé.
private struct PanWhenZoomed: ViewModifier {
    let enabled: Bool
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in lastOffset = offset }
            )
        } else {
            content
        }
    }
}

// MARK: - Partage iOS

#if os(iOS)
private struct GalleryShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
