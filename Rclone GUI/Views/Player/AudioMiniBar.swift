//
//  AudioMiniBar.swift
//  Rclone GUI — Views/Player
//
//  Mini-lecteur audio persistant (barre « en cours de lecture ») + vue plein
//  écran (pochette, scrubber, file de lecture). Piloté par AudioPlayback
//  Coordinator injecté à la racine ; survit à la navigation entre dossiers.
//

import SwiftUI
import CoreGraphics

// MARK: - Helpers

private func platformArtwork(_ cg: CGImage) -> Image {
    #if canImport(UIKit)
    return Image(uiImage: UIImage(cgImage: cg))
    #elseif canImport(AppKit)
    return Image(nsImage: NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height)))
    #else
    return Image(systemName: "music.note")
    #endif
}

private func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
}

@ViewBuilder
private func artworkView(_ cg: CGImage?, size: CGFloat, corner: CGFloat) -> some View {
    Group {
        if let cg {
            platformArtwork(cg)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [RG.accent.opacity(0.7), RG.accent.opacity(0.35)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
}

// MARK: - Mini-barre

struct AudioMiniBar: View {
    @EnvironmentObject private var audio: AudioPlaybackCoordinator
    @State private var showFullPlayer = false

    private var progress: Double {
        guard audio.duration > 0 else { return 0 }
        return min(1, max(0, audio.elapsed / audio.duration))
    }

    var body: some View {
        if audio.isActive {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.quaternary)
                        Rectangle().fill(RG.accent)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 2)

                HStack(spacing: 12) {
                    artworkView(audio.artwork, size: 40, corner: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(audio.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(audio.isLoading ? "Chargement…" : subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { showFullPlayer = true }

                    Button { audio.togglePlayPause() } label: {
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Button { Task { await audio.next() } } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 30, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(!audio.hasNext)

                    Button { audio.stop() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .sheet(isPresented: $showFullPlayer) {
                AudioPlayerSheet().environmentObject(audio)
            }
        }
    }

    private var subtitle: String {
        let total = audio.queue.count
        guard total > 1 else { return "En cours de lecture" }
        return "Piste \(audio.index + 1) sur \(total)"
    }
}

// MARK: - Vue plein écran

struct AudioPlayerSheet: View {
    @EnvironmentObject private var audio: AudioPlaybackCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 24) {
            handle

            artworkView(audio.artwork, size: 280, corner: 20)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text(audio.title)
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if audio.queue.count > 1 {
                    Text("Piste \(audio.index + 1) sur \(audio.queue.count)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)

            scrubber

            controls

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .presentationDragIndicator(.hidden)
        .onChange(of: audio.elapsed) { _, newValue in
            if !isScrubbing { scrubValue = newValue }
        }
        .onAppear { scrubValue = audio.elapsed }
    }

    private var handle: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: $scrubValue,
                in: 0...(max(audio.duration, 1)),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing { audio.seek(to: scrubValue) }
                }
            )
            .tint(RG.accent)
            .disabled(audio.duration <= 0)

            HStack {
                Text(timeString(scrubValue))
                Spacer()
                Text(timeString(audio.duration))
            }
            .font(RG.mono)
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 40) {
            Button { Task { await audio.previous() } } label: {
                Image(systemName: "backward.fill").font(.system(size: 26))
            }
            .buttonStyle(.plain)

            Button { audio.togglePlayPause() } label: {
                Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(RG.accent)
            }
            .buttonStyle(.plain)

            Button { Task { await audio.next() } } label: {
                Image(systemName: "forward.fill").font(.system(size: 26))
            }
            .buttonStyle(.plain)
            .disabled(!audio.hasNext)
        }
    }
}
