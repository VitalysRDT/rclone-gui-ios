//
//  VLCPlayerView.swift
//  Rclone GUI — Views/Player
//
//  Lecteur vidéo embarqué basé sur libVLC (VLCKit). Sert les formats
//  qu'AVPlayer ne sait pas décoder (MKV, AVI, WebM, TS…). Alimenté par
//  l'URL loopback HTTP seekable de RcloneStreamingService — donc streaming
//  par plages, crypt transparent, pas de téléchargement complet.
//
//  Contrôles maison : lecture/pause, barre de progression scrubbable,
//  sous-titres (sidecar + intégrés), pistes audio, vitesse, suivant/précédent.
//  Reprise de position + Now Playing/écran verrouillé gérés ici aussi.
//

import SwiftUI
import Combine

#if canImport(VLCKitSPM)
import VLCKitSPM

// MARK: - Model

/// Encapsule un `VLCMediaPlayer` et publie son état pour SwiftUI.
/// VLCKit délivre ses callbacks de délégué sur le thread principal, donc les
/// mutations de `@Published` y sont sûres.
final class VLCPlayerModel: NSObject, ObservableObject {
    // network-caching relevé à 8 s (défaut VLC = 1 s). Le flux arrive du bridge
    // loopback alimenté en SFTP (débit variable) ; un buffer large absorbe la
    // gigue et supprime les saccades sur les gros débits (ex. WEBRip 4K) — le
    // décodage 4K HEVC est matériel (VideoToolbox), le goulot est le réseau.
    let player = VLCMediaPlayer(options: ["--network-caching=8000"])

    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var failed = false
    @Published var positionSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var rate: Float = 1.0

    struct Track: Identifiable, Hashable {
        let id: Int32
        let name: String
    }
    @Published var subtitleTracks: [Track] = []
    @Published var audioTracks: [Track] = []
    @Published var currentSubtitleID: Int32 = -1
    @Published var currentAudioID: Int32 = -1

    /// Appelé quand la lecture atteint la fin (pour enchaîner la playlist).
    var onEnded: (() -> Void)?

    override init() {
        super.init()
        player.delegate = self
    }

    func attach(to drawable: Any) {
        player.drawable = drawable
    }

    func load(url: URL, startAtSeconds: Double?) {
        let media = VLCMedia(url: url)
        player.media = media
        player.play()
        if let start = startAtSeconds, start > 1 {
            // Appliqué quand la durée devient connue (= demuxer prêt), dans
            // refreshTime — un seek trop tôt sur un flux live est ignoré par VLC.
            resumeTargetSeconds = start
        }
    }

    private var resumeTargetSeconds: Double?

    func togglePlayPause() {
        if player.isPlaying { player.pause() } else { player.play() }
    }
    func play() { if !player.isPlaying { player.play() } }
    func pause() { if player.isPlaying { player.pause() } }

    func seek(toSeconds seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        player.time = VLCTime(int: Int32(seconds * 1000))
    }

    func skip(bySeconds delta: Double) {
        seek(toSeconds: max(0, positionSeconds + delta))
    }

    func setRate(_ newRate: Float) {
        player.rate = newRate
        rate = newRate
    }

    func selectSubtitle(id: Int32) {
        player.currentVideoSubTitleIndex = id
        currentSubtitleID = id
    }

    func selectAudio(id: Int32) {
        player.currentAudioTrackIndex = id
        currentAudioID = id
    }

    /// Ajoute un sous-titre externe (fichier local) et le sélectionne.
    func addExternalSubtitle(_ url: URL) {
        _ = player.addPlaybackSlave(url, type: .subtitle, enforce: true)
        // Les pistes seront rafraîchies au prochain changement d'état.
    }

    func stop() {
        player.delegate = nil
        player.stop()
    }

    private func refreshTracks() {
        let subIDs = (player.videoSubTitlesIndexes as? [NSNumber])?.map { $0.int32Value } ?? []
        let subNames = player.videoSubTitlesNames.map { String(describing: $0) }
        subtitleTracks = zip(subIDs, subNames).map { Track(id: $0.0, name: $0.1) }
        currentSubtitleID = player.currentVideoSubTitleIndex

        let audIDs = (player.audioTrackIndexes as? [NSNumber])?.map { $0.int32Value } ?? []
        let audNames = player.audioTrackNames.map { String(describing: $0) }
        audioTracks = zip(audIDs, audNames).map { Track(id: $0.0, name: $0.1) }
        currentAudioID = player.currentAudioTrackIndex
    }

    private func refreshTime() {
        // Nullabilité confirmée sur le header VLCKit (NS_ASSUME_NONNULL) :
        //   `time`  → VLCTime  (non-optionnel)
        //   `media` → VLCMedia? (nullable)
        //   `length`→ VLCTime  (non-optionnel)
        let ms = player.time.intValue
        positionSeconds = Double(ms) / 1000.0
        let lengthMs = player.media?.length.intValue ?? 0
        if lengthMs > 0 {
            durationSeconds = Double(lengthMs) / 1000.0
        } else if player.position > 0.0001 {
            // Estimation si la durée n'est pas encore connue.
            durationSeconds = positionSeconds / Double(player.position)
        }

        // Reprise différée : on seek une fois la durée réelle connue et que la
        // cible est bien avant la fin.
        if let target = resumeTargetSeconds, durationSeconds > 0, target < durationSeconds - 15 {
            resumeTargetSeconds = nil
            seek(toSeconds: target)
        } else if resumeTargetSeconds != nil, durationSeconds > 0 {
            // Durée connue mais cible hors plage → on abandonne la reprise.
            resumeTargetSeconds = nil
        }
    }
}

// MARK: VLCMediaPlayerDelegate

extension VLCPlayerModel: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        let state = player.state
        switch state {
        case .buffering, .opening:
            isBuffering = true
        case .playing:
            isBuffering = false
            isPlaying = true
            failed = false
            refreshTracks()
            // La reprise est appliquée dans refreshTime() une fois la durée
            // connue (le demuxer est alors prêt à seek).
        case .paused:
            isPlaying = false
        case .stopped:
            isPlaying = false
        case .ended:
            isPlaying = false
            onEnded?()
        case .error:
            failed = true
            isBuffering = false
            isPlaying = false
        default:
            // .esAdded et autres : mettre à jour les pistes au cas où.
            refreshTracks()
        }
        rate = player.rate
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        refreshTime()
    }
}

// MARK: - Drawable surface

#if canImport(UIKit)
import UIKit

private struct VLCDrawableRepresentable: UIViewRepresentable {
    let model: VLCPlayerModel
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        model.attach(to: view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#elseif canImport(AppKit)
import AppKit

private struct VLCDrawableRepresentable: NSViewRepresentable {
    let model: VLCPlayerModel
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        model.attach(to: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

// MARK: - Embedded player view

struct EmbeddedVLCPlayerView: View {
    let streamURL: URL
    let title: String
    let remote: String
    let path: String
    let subtitles: [SidecarSubtitle]

    var hasNext: Bool = false
    var hasPrevious: Bool = false
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onOpenExternal: (() -> Void)?
    var onClose: (() -> Void)?

    @StateObject private var model = VLCPlayerModel()
    @State private var showControls = true
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var lastSavedSecond: Int = -1
    @State private var loadingSubtitle = false

    private let speeds: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VLCDrawableRepresentable(model: model)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                }

            if model.isBuffering && !model.failed {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
            }

            if model.failed {
                failureOverlay
            } else if showControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .task {
            // La session audio est possédée par MediaPlayerHost (évite une
            // course de désactivation lors des enchaînements de playlist).
            let resume = PlaybackProgressStore.resumePosition(remote: remote, path: path)
            model.load(url: streamURL, startAtSeconds: resume)
            model.onEnded = {
                PlaybackProgressStore.clear(remote: remote, path: path)
                if let onNext { onNext() } else { onClose?() }
            }
            configureRemoteCommands()
        }
        .onChange(of: model.positionSeconds) { _, newValue in
            if !scrubbing { scrubValue = newValue }
            persistAndPublish(position: newValue)
        }
        .onChange(of: model.isPlaying) { _, _ in
            updateNowPlaying()
        }
        .task(id: autoHideKey) {
            // Auto-masquage des contrôles après 4 s, dès que la lecture tourne.
            // Clé sur (showControls, isPlaying) pour se relancer quand l'un
            // ou l'autre change (sinon le démarrage de lecture ne relancerait
            // pas la tâche).
            guard showControls, model.isPlaying else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled, model.isPlaying {
                withAnimation(.easeInOut(duration: 0.3)) { showControls = false }
            }
        }
        .onDisappear {
            PlaybackProgressStore.save(
                remote: remote, path: path,
                position: model.positionSeconds, duration: model.durationSeconds
            )
            model.stop()
            // La session audio (et les commandes distantes) sont fermées par
            // MediaPlayerHost à la sortie complète, pas ici.
        }
        #if os(iOS)
        .statusBarHidden(!showControls)
        #endif
    }

    // MARK: Controls

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            centerTransport
            Spacer()
            bottomBar
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                onClose?()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.35), in: .circle)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            trackMenus
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var centerTransport: some View {
        HStack(spacing: 46) {
            Button { model.skip(bySeconds: -10) } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.white)
            }
            Button { model.togglePlayPause() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
            }
            Button { model.skip(bySeconds: 10) } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.white)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(timeString(scrubbing ? scrubValue : model.positionSeconds))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))

                Slider(
                    value: $scrubValue,
                    in: 0...max(model.durationSeconds, 1),
                    onEditingChanged: { editing in
                        scrubbing = editing
                        if !editing { model.seek(toSeconds: scrubValue) }
                    }
                )
                .tint(.white)

                Text(timeString(model.durationSeconds))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            }

            HStack(spacing: 20) {
                if hasPrevious {
                    Button { onPrevious?() } label: {
                        Image(systemName: "backward.end.fill").foregroundStyle(.white)
                    }
                }
                speedMenu
                Spacer()
                if let onOpenExternal {
                    Button { onOpenExternal() } label: {
                        Label("Externe", systemImage: "play.rectangle.on.rectangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                if hasNext {
                    Button { onNext?() } label: {
                        Image(systemName: "forward.end.fill").foregroundStyle(.white)
                    }
                }
            }
            .font(.system(size: 16))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }

    private var trackMenus: some View {
        HStack(spacing: 8) {
            // Sous-titres : sidecar + intégrés.
            Menu {
                Button {
                    model.selectSubtitle(id: -1)
                } label: {
                    Label("Désactivés", systemImage: model.currentSubtitleID == -1 ? "checkmark" : "")
                }
                if !model.subtitleTracks.isEmpty {
                    Section("Pistes intégrées") {
                        ForEach(model.subtitleTracks) { track in
                            if track.id != -1 {
                                Button {
                                    model.selectSubtitle(id: track.id)
                                } label: {
                                    Label(track.name, systemImage: model.currentSubtitleID == track.id ? "checkmark" : "")
                                }
                            }
                        }
                    }
                }
                if !subtitles.isEmpty {
                    Section("Fichiers à côté") {
                        ForEach(subtitles) { sub in
                            Button {
                                addSidecarSubtitle(sub)
                            } label: {
                                Text(sub.language.map { "\(sub.name) (\($0))" } ?? sub.name)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(model.currentSubtitleID != -1 ? Color.accentColor : .white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.35), in: .circle)
            }

            // Pistes audio (si plusieurs).
            if model.audioTracks.count > 1 {
                Menu {
                    ForEach(model.audioTracks) { track in
                        Button {
                            model.selectAudio(id: track.id)
                        } label: {
                            Label(track.name, systemImage: model.currentAudioID == track.id ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.35), in: .circle)
                }
            }
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach(speeds, id: \.self) { speed in
                Button {
                    model.setRate(speed)
                } label: {
                    Label(speedLabel(speed), systemImage: model.rate == speed ? "checkmark" : "")
                }
            }
        } label: {
            Text(speedLabel(model.rate))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.35), in: .capsule)
        }
    }

    private var failureOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Lecture impossible")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text("Ce fichier n'a pas pu être lu dans l'app.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if let onOpenExternal {
                Button {
                    onOpenExternal()
                } label: {
                    Label("Ouvrir dans une app externe", systemImage: "play.rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            Button("Fermer") { onClose?() }
                .foregroundStyle(.white)
        }
        .padding(28)
    }

    // MARK: Helpers

    private func addSidecarSubtitle(_ sub: SidecarSubtitle) {
        guard !loadingSubtitle else { return }
        loadingSubtitle = true
        Task {
            defer { loadingSubtitle = false }
            if let url = try? await SubtitleService.shared.localURL(remote: remote, subtitle: sub) {
                model.addExternalSubtitle(url)
            }
        }
    }

    private var autoHideKey: String {
        "\(showControls)|\(model.isPlaying)"
    }

    private func persistAndPublish(position: Double) {
        let second = Int(position)
        if second != lastSavedSecond, second % 5 == 0 {
            lastSavedSecond = second
            PlaybackProgressStore.save(
                remote: remote, path: path,
                position: position, duration: model.durationSeconds
            )
            updateNowPlaying()
        }
    }

    private func updateNowPlaying() {
        NowPlayingService.shared.updateNowPlaying(
            title: title,
            durationSeconds: model.durationSeconds,
            elapsedSeconds: model.positionSeconds,
            rate: model.isPlaying ? model.rate : 0
        )
    }

    private func configureRemoteCommands() {
        NowPlayingService.shared.configureRemoteCommands(
            onPlay: { model.play() },
            onPause: { model.pause() },
            onNext: hasNext ? { onNext?() } : nil,
            onPrevious: hasPrevious ? { onPrevious?() } : nil,
            onSeek: { model.seek(toSeconds: $0) }
        )
    }

    private func speedLabel(_ speed: Float) -> String {
        speed == 1.0 ? "1×" : String(format: "%g×", speed)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

#else

// MARK: - Stub (VLCKit absent du build)

/// Repli si le package VLCKit n'est pas (encore) lié : on n'a pas de lecteur
/// logiciel, donc on propose l'ouverture externe.
struct EmbeddedVLCPlayerView: View {
    let streamURL: URL
    let title: String
    let remote: String
    let path: String
    let subtitles: [SidecarSubtitle]
    var hasNext: Bool = false
    var hasPrevious: Bool = false
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onOpenExternal: (() -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "film.stack")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Lecteur VLC indisponible")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Le module de lecture multi-format n'est pas inclus dans ce build.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                if let onOpenExternal {
                    Button {
                        onOpenExternal()
                    } label: {
                        Label("Ouvrir dans une app externe", systemImage: "play.rectangle.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Fermer") { onClose?() }
                    .foregroundStyle(.white)
            }
            .padding(28)
        }
    }
}

#endif
