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
    // Buffer réseau 2,5 s : petit volontairement pour une OUVERTURE RAPIDE (un
    // buffer plus gros = VLC attend de le remplir avant la 1re image). Le
    // grésillement audio « plusieurs fois/seconde » n'est PAS un manque de débit
    // (déficit=0, la vidéo tient) mais un artefact du pipeline audio → réglé par
    // --no-audio-time-stretch, pas par le buffer. avcodec-hw=videotoolbox FORCE
    // le décodage MATÉRIEL (sinon VLC retombe en soft sur la 2160p).
    static let networkCachingMs = 2500
    let player = VLCMediaPlayer(options: [
        "--network-caching=\(VLCPlayerModel.networkCachingMs)",
        "--avcodec-hw=videotoolbox",
        // ANTI-IMAGES-PERDUES après un seek sur flux réseau (SFTP loopback) :
        // la livraison par à-coups fait jitter l'horloge d'entrée → VLC croit
        // être en retard EN PERMANENCE et drop les frames (imgPerdues=635 vu en
        // prod alors que réseau≈5–14 Mbit/s pour 3,6 requis). clock-jitter=0
        // neutralise cette compensation ; no-drop-late-frames empêche de jeter
        // des images en réalité décodées à temps (VideoToolbox tient le 1080p).
        "--clock-jitter=0",
        "--no-drop-late-frames",
        // ANTI-GRÉSILLEMENT AUDIO (plusieurs clics/seconde) : le time-stretch
        // audio (scaletempo, ON par défaut) ré-étire l'audio en PERMANENCE quand
        // l'horloge micro-corrige sur un flux SFTP jittery → artefacts continus.
        // On le désactive : VLC laisse le pitch tel quel au lieu d'artefacter.
        "--no-audio-time-stretch",
    ])

    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var failed = false
    @Published var positionSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var rate: Float = 1.0

    struct Track: Identifiable, Hashable {
        // VLCKit 4.0 : les pistes sont identifiées par un trackId String
        // (ex. "audio/0"), plus par un index Int32 comme en 3.x.
        let id: String
        let name: String
    }
    @Published var subtitleTracks: [Track] = []
    @Published var audioTracks: [Track] = []
    /// trackId de la piste sélectionnée, nil = aucune (sous-titres désactivés).
    @Published var currentSubtitleID: String?
    @Published var currentAudioID: String?

    /// Appelé quand la lecture atteint la fin (pour enchaîner la playlist).
    var onEnded: (() -> Void)?

    // MARK: PiP (VLCKit 4.0)
    /// True quand VLCKit a fourni le contrôleur de fenêtre PiP → PiP activable.
    @Published var pipReady = false
    /// Contrôleur de fenêtre PiP fourni par VLCKit (start/stop/invalidate).
    private var pipWindow: (any VLCPictureInPictureWindowControlling)?

    func setPiPWindow(_ controller: any VLCPictureInPictureWindowControlling) {
        pipWindow = controller
        pipReady = true
    }
    func startPiP() { pipWindow?.startPictureInPicture() }
    func stopPiP() { pipWindow?.stopPictureInPicture() }
    /// À appeler quand l'état de lecture change pour rafraîchir l'UI PiP.
    func invalidatePiP() { pipWindow?.invalidatePlaybackState() }

    override init() {
        super.init()
        player.delegate = self
    }

    func attach(to drawable: Any) {
        player.drawable = drawable
    }

    func load(url: URL, startAtSeconds: Double?) {
        loadStartedAt = Date()
        // Repart propre pour la détection d'avancée (sinon un ancien tick fausse
        // le 1er calcul de stall sur le nouveau média).
        prevTickPosition = -1
        lastAdvanceAt = .distantPast
        underrunDeficit = 0
        underrunTriggered = false
        lastSeekAt = .distantPast
        let sizeText = sizeBytes > 0
            ? ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
            : "?"
        plog("▶︎ VLC load — fichier=\(sizeText) network-caching=\(VLCPlayerModel.networkCachingMs)ms hw=videotoolbox url=\(url.scheme ?? "")")
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

    // MARK: - Télémétrie (diagnostic saccades / débit)
    /// Taille du fichier distant (octets) pour calculer le bitrate moyen requis.
    var sizeBytes: Int64 = 0
    private var loadStartedAt: Date?
    private var firstFrameAt: Date?
    private var bufferingStartedAt: Date?
    private var stallCount = 0
    private var totalStallSeconds: Double = 0
    private var lastStatLogAt: Date?
    private var lastKeepUpPos: Double?
    private var lastKeepUpWall: Date?
    private var lastReadBytes: Int = 0

    // Détection de VRAI stall vs `.buffering` nominal : VLC repasse en
    // `.buffering` même quand la vidéo DÉFILE (typiquement après un seek), ce qui
    // collait la roue. On se fie à l'avancée RÉELLE de la position plutôt qu'à
    // l'état nominal de VLC : la roue ne s'affiche que si la position est figée.
    private var prevTickPosition: Double = -1
    private var lastAdvanceAt: Date = .distantPast

    // Surveillance de santé du flux : si la lecture EN STREAMING n'arrive pas à
    // tenir le temps réel de façon SOUTENUE (sous-alimentation SFTP qui dip sous
    // le bitrate → saccade), on bascule vers le téléchargement local (lecture
    // parfaite, seeks instantanés). Actif uniquement en streaming, armé une fois.
    var monitorsStreamHealth = false
    var onSustainedUnderrun: (() -> Void)?
    private var underrunDeficit: Double = 0
    private var underrunTriggered = false
    private var lastSeekAt: Date = .distantPast

    private func plog(_ message: String) {
        Task { await LogService.shared.log(.info, category: "player", message: message) }
    }

    private func stateName(_ s: VLCMediaPlayerState) -> String {
        switch s {
        case .stopped: return "stopped"
        case .stopping: return "stopping"
        case .opening: return "opening"
        case .buffering: return "buffering"
        case .error: return "error"
        case .playing: return "playing"
        case .paused: return "paused"
        @unknown default: return "?"
        }
    }

    /// Bitrate moyen requis = taille×8 / durée. Le débit réseau doit le dépasser
    /// pour une lecture fluide.
    private func avgBitrateMbps() -> Double? {
        guard sizeBytes > 0, durationSeconds > 1 else { return nil }
        return Double(sizeBytes) * 8 / durationSeconds / 1_000_000
    }

    func togglePlayPause() {
        if player.isPlaying { player.pause() } else { player.play() }
    }
    func play() { if !player.isPlaying { player.play() } }
    func pause() { if player.isPlaying { player.pause() } }

    func seek(toSeconds seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        lastSeekAt = Date()   // grâce : le re-remplissage post-seek ne compte pas comme underrun
        player.time = VLCTime(int: Int32(seconds * 1000))
    }

    func skip(bySeconds delta: Double) {
        seek(toSeconds: max(0, positionSeconds + delta))
    }

    func setRate(_ newRate: Float) {
        player.rate = newRate
        rate = newRate
    }

    func selectSubtitle(id: String?) {
        if let id, let track = player.textTracks.first(where: { $0.trackId == id }) {
            track.isSelectedExclusively = true
            currentSubtitleID = id
        } else {
            player.deselectAllTextTracks()   // id nil = sous-titres désactivés
            currentSubtitleID = nil
        }
    }

    func selectAudio(id: String) {
        if let track = player.audioTracks.first(where: { $0.trackId == id }) {
            track.isSelectedExclusively = true
            currentAudioID = id
        }
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

    /// Arrête le flux en cours SANS retirer le delegate, pour pouvoir recharger
    /// ensuite sur le fichier local. À appeler avant un téléchargement afin de
    /// libérer rclone (sinon stream + download saturent le même process).
    func haltForDownload() {
        player.stop()
    }

    private func refreshTracks() {
        // VLCKit 4.0 : pistes via player.textTracks / audioTracks (VLCMediaPlayerTrack
        // avec trackId/trackName/isSelected), au lieu des index 3.x.
        let subs = player.textTracks
        subtitleTracks = subs.map { Track(id: $0.trackId, name: $0.trackName) }
        currentSubtitleID = subs.first(where: { $0.isSelected })?.trackId

        let auds = player.audioTracks
        audioTracks = auds.map { Track(id: $0.trackId, name: $0.trackName) }
        currentAudioID = auds.first(where: { $0.isSelected })?.trackId
    }

    private func refreshTime() {
        // Nullabilité confirmée sur le header VLCKit (NS_ASSUME_NONNULL) :
        //   `time`  → VLCTime  (non-optionnel)
        //   `media` → VLCMedia? (nullable)
        //   `length`→ VLCTime  (non-optionnel)
        let ms = player.time.intValue
        positionSeconds = Double(ms) / 1000.0

        // La position a-t-elle avancé depuis le dernier tick ? Si oui, la lecture
        // PROGRESSE réellement → on lève la roue, même si VLC se dit `.buffering`.
        if prevTickPosition >= 0, positionSeconds > prevTickPosition + 0.05 {
            lastAdvanceAt = Date()
            if isBuffering { isBuffering = false }
        }
        prevTickPosition = positionSeconds

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

        logPeriodicStats()
    }

    /// Toutes les ~3 s : « % temps réel » (la position avance-t-elle aussi vite
    /// que l'horloge ?), bitrate moyen requis, et stats réseau VLC (débit réseau
    /// vs demux + images perdues) → distingue « lien trop lent » de « décodage ».
    private func logPeriodicStats() {
        let now = Date()
        let sinceLast = lastStatLogAt.map { now.timeIntervalSince($0) }
        if let s = sinceLast, s < 3 { return }

        var keepUp = "?"
        if let lp = lastKeepUpPos, let lw = lastKeepUpWall {
            let posDelta = positionSeconds - lp
            let wallDelta = now.timeIntervalSince(lw)
            if wallDelta > 0.1 {
                keepUp = String(format: "%.0f%%", max(0, posDelta / wallDelta) * 100)
                evaluateStreamHealth(posDelta: posDelta, wallDelta: wallDelta, now: now)
            }
        }
        lastKeepUpPos = positionSeconds
        lastKeepUpWall = now
        lastStatLogAt = now

        var line = "VLC 📊 pos=\(Int(positionSeconds))/\(Int(durationSeconds))s tempsRéel=\(keepUp) état=\(stateName(player.state))"
        if let br = avgBitrateMbps() { line += " bitrateMoyen=\(String(format: "%.1f", br))Mbit/s" }
        if let stats = player.media?.statistics {
            // Débit réseau RÉEL = delta des octets lus / temps (le champ
            // inputBitrate de VLC renvoie 0 ici ; readBytes, lui, est fiable).
            let read = Int(stats.readBytes)
            var netStr = "?"
            if let dt = sinceLast, dt > 0.1, read >= lastReadBytes {
                let mbps = Double(read - lastReadBytes) * 8 / dt / 1_000_000
                netStr = String(format: "%.1f", mbps)
            }
            lastReadBytes = read
            line += " | réseau≈\(netStr)Mbit/s lus=\(read / 1_048_576)Mo imgPerdues=\(stats.lostPictures)"
        }
        if monitorsStreamHealth {
            // Déficit temps-réel cumulé : quand il dépasse 4 s, bascule auto download.
            line += " déficit=\(String(format: "%.1f", underrunDeficit))s/4"
        }
        plog(line)
    }

    /// Accumule le « retard » de la lecture streaming vs le temps réel. Quand le
    /// flux SFTP ne suit pas durablement (déficit cumulé >4 s = saccade visible),
    /// déclenche UNE fois la bascule vers le téléchargement local. Les pics de
    /// rattrapage réduisent le déficit (amorti) : un flux qui récupère vite ne
    /// déclenche pas. Grâce de 8 s après la 1re image et 4 s après chaque seek
    /// (le re-remplissage est normal et ne doit pas compter).
    private func evaluateStreamHealth(posDelta: Double, wallDelta: Double, now: Date) {
        guard monitorsStreamHealth, !underrunTriggered, firstFrameAt != nil else { return }
        let sinceFirstFrame = firstFrameAt.map { now.timeIntervalSince($0) } ?? 0
        guard sinceFirstFrame > 8,
              now.timeIntervalSince(lastSeekAt) > 4,
              wallDelta < 10, posDelta >= -0.5 else { return }
        if posDelta < wallDelta {
            underrunDeficit += (wallDelta - posDelta)                        // tombé en retard
        } else {
            underrunDeficit = max(0, underrunDeficit - (posDelta - wallDelta) * 0.5)  // rattrape (amorti)
        }
        if underrunDeficit > 4.0 {
            underrunTriggered = true
            monitorsStreamHealth = false
            plog("VLC ⚠️ flux insuffisant (déficit \(String(format: "%.1f", underrunDeficit))s) → bascule téléchargement local")
            onSustainedUnderrun?()
        }
    }
}

// MARK: VLCMediaPlayerDelegate

extension VLCPlayerModel: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        // VLCKit 4.0 : le delegate reçoit l'état directement (avant : une Notification).
        let state = newState
        plog("VLC état → \(stateName(state)) @\(Int(positionSeconds))s (stalls=\(stallCount), totalStall=\(String(format: "%.1f", totalStallSeconds))s)")
        switch state {
        case .buffering, .opening:
            // VLC émet des .buffering MÊME quand la vidéo DÉFILE (remplissage de
            // buffer, et surtout après un seek) → se fier à `!isPlaying` collait
            // la roue alors que la position avançait. On ne montre la roue que sur
            // un VRAI stall : pas en lecture ET position figée depuis >1,5 s.
            let recentlyAdvanced = Date().timeIntervalSince(lastAdvanceAt) < 1.5
            let stalled = !player.isPlaying && !recentlyAdvanced
            if state == .buffering, stalled, bufferingStartedAt == nil {
                bufferingStartedAt = Date()
                if firstFrameAt != nil { stallCount += 1 }  // vrai re-buffer après le 1er frame
            }
            isBuffering = stalled
        case .playing:
            isBuffering = false
            isPlaying = true
            failed = false
            if firstFrameAt == nil {
                firstFrameAt = Date()
                let ttf = loadStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                plog("VLC ⏱️ 1re image après \(String(format: "%.1f", ttf))s ; bitrate moyen=\(avgBitrateMbps().map { String(format: "%.1f Mbit/s", $0) } ?? "?")")
            }
            if let s = bufferingStartedAt {
                let dur = Date().timeIntervalSince(s)
                totalStallSeconds += dur
                bufferingStartedAt = nil
                plog("VLC ⚠️ fin re-buffering après \(String(format: "%.1f", dur))s (stall #\(stallCount))")
            }
            refreshTracks()
            plog("🔊 audio: \(audioTracks.count) piste(s) sél=\(currentAudioID ?? "-") · sous-titres: \(subtitleTracks.count) — VLC=[caching=\(Self.networkCachingMs)ms, hw=videotoolbox, clock-jitter=0, no-drop-late-frames, no-audio-time-stretch]")
        case .paused:
            isPlaying = false
        case .stopping:
            isPlaying = false
        case .stopped:
            isPlaying = false
            plog("VLC ⏹️ stop — bilan : stalls=\(stallCount), tempsBuffering=\(String(format: "%.1f", totalStallSeconds))s")
            // VLCKit 4.0 n'a plus d'état .ended : fin de média = .stopped en étant
            // proche de la fin → on enchaîne la playlist.
            if durationSeconds > 0, positionSeconds >= durationSeconds - 2 {
                onEnded?()
            }
        case .error:
            failed = true
            isBuffering = false
            isPlaying = false
            plog("VLC ❌ erreur de lecture @\(Int(positionSeconds))s")
        default:
            // autres états : mettre à jour les pistes au cas où.
            refreshTracks()
        }
        rate = player.rate
        invalidatePiP()   // l'UI PiP (play/pause/durée) suit l'état de lecture
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        refreshTime()
    }
}

// MARK: - PiP media controller (VLCKit 4.0)

/// Pont entre le PiP de VLCKit et le VLCMediaPlayer : VLCKit appelle ces méthodes
/// pour piloter la lecture et afficher l'état dans la mini-fenêtre PiP.
final class VLCPiPMediaController: NSObject, VLCPictureInPictureMediaControlling {
    private weak var player: VLCMediaPlayer?
    init(player: VLCMediaPlayer) { self.player = player; super.init() }
    func play() { player?.play() }
    func pause() { player?.pause() }
    func seek(by offset: Int64, completion: @escaping () -> Void) {
        if let player {
            let target = Int64(player.time.intValue) + offset   // offset en ms
            player.time = VLCTime(int: Int32(clamping: target))
        }
        completion()
    }
    func mediaLength() -> Int64 { Int64(player?.media?.length.intValue ?? 0) }
    func mediaTime() -> Int64 { Int64(player?.time.intValue ?? 0) }
    func isMediaSeekable() -> Bool { player?.isSeekable ?? false }
    func isMediaPlaying() -> Bool { player?.isPlaying ?? false }
}

// MARK: - Drawable surface (conforme PiP VLCKit 4.0)

#if canImport(UIKit)
import UIKit

/// Vue hôte du rendu VLC, conforme à VLCPictureInPictureDrawable → active le PiP
/// natif de VLCKit 4.0 (VLCKit gère AVPictureInPictureController en interne).
private final class VLCPiPDrawableUIView: UIView, VLCPictureInPictureDrawable {
    let pipMediaController: VLCPiPMediaController
    var onWindowReady: ((any VLCPictureInPictureWindowControlling) -> Void)?
    init(player: VLCMediaPlayer) {
        pipMediaController = VLCPiPMediaController(player: player)
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non supporté") }
    func mediaController() -> (any VLCPictureInPictureMediaControlling)! { pipMediaController }
    func pictureInPictureReady() -> ((any VLCPictureInPictureWindowControlling)?) -> Void {
        { [weak self] controller in
            if let controller { self?.onWindowReady?(controller) }
        }
    }
}

private struct VLCDrawableRepresentable: UIViewRepresentable {
    let model: VLCPlayerModel
    func makeUIView(context: Context) -> VLCPiPDrawableUIView {
        let view = VLCPiPDrawableUIView(player: model.player)
        view.backgroundColor = .black
        view.onWindowReady = { [weak model] controller in
            Task { @MainActor in model?.setPiPWindow(controller) }
        }
        model.attach(to: view)
        return view
    }
    func updateUIView(_ uiView: VLCPiPDrawableUIView, context: Context) {}
}
#elseif canImport(AppKit)
import AppKit

private final class VLCPiPDrawableNSView: NSView, VLCPictureInPictureDrawable {
    let pipMediaController: VLCPiPMediaController
    var onWindowReady: ((any VLCPictureInPictureWindowControlling) -> Void)?
    init(player: VLCMediaPlayer) {
        pipMediaController = VLCPiPMediaController(player: player)
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non supporté") }
    func mediaController() -> (any VLCPictureInPictureMediaControlling)! { pipMediaController }
    func pictureInPictureReady() -> ((any VLCPictureInPictureWindowControlling)?) -> Void {
        { [weak self] controller in
            if let controller { self?.onWindowReady?(controller) }
        }
    }
}

private struct VLCDrawableRepresentable: NSViewRepresentable {
    let model: VLCPlayerModel
    func makeNSView(context: Context) -> VLCPiPDrawableNSView {
        let view = VLCPiPDrawableNSView(player: model.player)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.onWindowReady = { [weak model] controller in
            Task { @MainActor in model?.setPiPWindow(controller) }
        }
        model.attach(to: view)
        return view
    }
    func updateNSView(_ nsView: VLCPiPDrawableNSView, context: Context) {}
}
#endif

// MARK: - Embedded player view

struct EmbeddedVLCPlayerView: View {
    let streamURL: URL
    let title: String
    let remote: String
    let path: String
    let subtitles: [SidecarSubtitle]
    var sizeHint: Int64 = 0

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
    // Télécharger-puis-lire : quand le streaming d'un MKV galère (seek-heavy en
    // SFTP), on télécharge le fichier en séquentiel (rapide) et on relit en local
    // (zéro seek). Auto-proposé après un buffering prolongé.
    @State private var downloading = false
    @State private var downloadError: String?
    @State private var playingLocal = false
    @State private var bufferingSince: Date?
    @State private var offerLocalDownload = false

    private let speeds: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VLCDrawableRepresentable(model: model)
                .ignoresSafeArea()

            // Couche de tap plein écran : poser un .onTapGesture directement sur
            // le UIViewRepresentable VLC n'est PAS fiable — le UIView hôte de VLC
            // avale le touch, donc le tap ne montrait jamais les contrôles. Cette
            // couche transparente (au-dessus de la vidéo, SOUS les contrôles)
            // capte le tap de façon fiable.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                }

            if downloading {
                downloadingOverlay
            } else if model.isBuffering && !model.failed {
                bufferingOverlay
            }

            if model.failed && !downloading {
                failureOverlay
            } else if showControls && !downloading {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .task {
            // La session audio est possédée par MediaPlayerHost (évite une
            // course de désactivation lors des enchaînements de playlist).
            model.sizeBytes = sizeHint
            model.onEnded = {
                PlaybackProgressStore.clear(remote: remote, path: path)
                if let onNext { onNext() } else { onClose?() }
            }
            configureRemoteCommands()
            // STREAMING EN BUFFER PAR DÉFAUT : on lit le flux loopback par plages
            // (network-caching), SANS télécharger tout le fichier. Le download
            // complet (URLSession aspirant les 4,7 Go d'un coup) saturait le
            // runtime Go de librclone et FIGEAIT l'app — les autres RPC traînaient
            // derrière. Si le fichier est déjà en cache (« Télécharger pour lire »
            // utilisé avant), on le relit en local — instantané. Sinon on streame ;
            // « Télécharger pour lire » reste proposé en repli si un gros MKV 4K
            // seek-heavy galère (auto-proposé après 12 s de buffering).
            let resume = PlaybackProgressStore.resumePosition(remote: remote, path: path)
            let cached = MediaCacheService.cacheURL(remote: remote, path: path)
            if FileManager.default.fileExists(atPath: cached.path) {
                plog("🎬 source=CACHE LOCAL — \(cached.lastPathComponent) resume=\(Int(resume ?? 0))s (lecture instantanée)")
                playingLocal = true
                model.load(url: cached, startAtSeconds: resume)
            } else {
                // Streaming PUR depuis le bridge rclone (serveur HTTP range natif,
                // éprouvé). Démarrage RAPIDE, zéro code maison. Si le débit SFTP ne
                // tient pas de façon soutenue (mesuré), bascule auto vers le
                // téléchargement complet puis lecture locale.
                plog("🎬 source=STREAMING (pas en cache)")
                startStreaming(resume: resume)
            }
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
        .task(id: model.isBuffering) {
            // Buffering qui s'éternise (streaming MKV seek-heavy) → on propose
            // « Télécharger pour lire » après 12 s. Réinitialisé dès que ça joue.
            guard model.isBuffering, !playingLocal, !downloading else {
                offerLocalDownload = false
                return
            }
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled, model.isBuffering, !playingLocal, !downloading {
                withAnimation { offerLocalDownload = true }
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
        // AUTO-PiP en quittant l'app : quand l'app passe en arrière-plan pendant
        // une lecture, on démarre le Picture-in-Picture → la VIDÉO continue en
        // vignette flottante (avant : seul l'audio continuait). C'est la réponse
        // exacte à « quand on quitte l'app on a l'audio mais pas la vidéo ».
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if model.pipReady, model.isPlaying { model.startPiP() }
        }
        #endif
    }

    // MARK: Télécharger pour lire

    private var bufferingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.4)
            if offerLocalDownload {
                VStack(spacing: 10) {
                    Text("La lecture en streaming a du mal sur ce fichier.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                    Button { downloadAndPlayLocal() } label: {
                        Label("Télécharger pour lire", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(RG.accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .transition(.opacity)
            }
        }
    }

    private var downloadingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.4)
            Text("Téléchargement pour une lecture fluide…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text("La lecture locale démarre sans saccade dès que c'est prêt. Pour un gros fichier 4K, ça peut prendre quelques minutes.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            if let downloadError {
                Text(downloadError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
            Button { onClose?() } label: {
                Text("Fermer (le téléchargement continue en arrière-plan)")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    /// Log côté VUE (catégorie "player") pour suivre tout le parcours sur device.
    private func plog(_ message: String) {
        Task { await LogService.shared.log(.info, category: "player", message: message) }
    }

    /// Streaming direct depuis le bridge rclone (serveur HTTP range natif) +
    /// moniteur de santé : si le flux ne tient pas le débit de façon SOUTENUE
    /// (saccade mesurée), bascule auto vers le téléchargement complet puis lecture
    /// locale (parfaite, seeks instantanés). Le plus robuste : aucun proxy maison.
    private func startStreaming(resume: Double?) {
        // MÉTHODE UNIQUE = streaming. Plus de bascule auto vers download (le réseau
        // tient) ; le bouton « Télécharger pour lire » reste en secours manuel.
        plog("▶︎ STREAMING (méthode unique) — buffer \(VLCPlayerModel.networkCachingMs)ms — resume=\(Int(resume ?? 0))s sizeHint=\(sizeHint / 1_048_576)Mo url=\(streamURL.absoluteString)")
        model.load(url: streamURL, startAtSeconds: resume)
    }

    /// Télécharge le fichier complet en local puis bascule la lecture dessus —
    /// zéro seek, démux parfait. Déclenché par le moniteur de santé (débit
    /// insuffisant) ou le bouton manuel. Le cache LRU MediaCache gère la rétention.
    private func downloadAndPlayLocal() {
        guard !downloading else { return }
        downloading = true
        downloadError = nil
        offerLocalDownload = false
        model.monitorsStreamHealth = false   // on quitte le streaming → coupe le moniteur
        // Libère rclone : on arrête le flux pour qu'il ne fasse QUE le download.
        model.haltForDownload()
        plog("⬇️ BASCULE téléchargement complet → lecture locale (débit streaming insuffisant ou demande manuelle)")
        Task {
            let startedAt = Date()
            do {
                let url = try await MediaCacheService.shared.localPlayableURL(
                    remote: remote, path: path, sizeHint: sizeHint, policy: .reuseIfCached
                )
                plog("⬇️ téléchargement OK en \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s → lecture locale \(url.lastPathComponent)")
                await MainActor.run {
                    downloading = false
                    playingLocal = true
                    let resume = PlaybackProgressStore.resumePosition(remote: remote, path: path)
                    model.sizeBytes = sizeHint
                    model.load(url: url, startAtSeconds: resume)
                }
            } catch {
                plog("⬇️ ÉCHEC téléchargement après \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s : \(error.localizedDescription)")
                await MainActor.run {
                    downloading = false
                    downloadError = error.localizedDescription
                }
            }
        }
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
            if model.pipReady {
                Button { model.startPiP() } label: {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.35), in: .circle)
                }
                .accessibilityLabel("Picture-in-Picture")
            }
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
                    model.selectSubtitle(id: nil)
                } label: {
                    Label("Désactivés", systemImage: model.currentSubtitleID == nil ? "checkmark" : "")
                }
                if !model.subtitleTracks.isEmpty {
                    Section("Pistes intégrées") {
                        ForEach(model.subtitleTracks) { track in
                            Button {
                                model.selectSubtitle(id: track.id)
                            } label: {
                                Label(track.name, systemImage: model.currentSubtitleID == track.id ? "checkmark" : "")
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
                    .foregroundStyle(model.currentSubtitleID != nil ? Color.accentColor : .white)
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
