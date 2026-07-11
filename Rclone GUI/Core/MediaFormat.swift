//
//  MediaFormat.swift
//  Rclone GUI — Core
//
//  Source unique de vérité pour : « est-ce un média ? », « vidéo vs audio ? »
//  et surtout « quel moteur de lecture ? ».
//
//  Le lecteur in-app est *hybride* :
//    - AVFoundation (AVPlayer) pour ce qu'Apple décode nativement
//      (MP4/MOV/M4V + audio courant) → PiP, décodage matériel, batterie,
//      AirPlay, sélecteur de sous-titres natif.
//    - libVLC (VLCKit) pour tout le reste (MKV/AVI/WebM/TS…) qu'AVPlayer
//      ne sait pas ouvrir — sinon l'utilisateur n'a qu'un écran noir.
//

import Foundation
import UniformTypeIdentifiers

/// Moteur de lecture in-app retenu pour un fichier donné.
public enum PlaybackEngine: Sendable, Equatable {
    /// AVPlayer / AVKit — conteneurs et codecs supportés nativement par Apple.
    case avFoundation
    /// libVLC — décodage logiciel pour les formats qu'AVPlayer refuse.
    case vlc
}

/// Utilitaire pur (calculs sur des données statiques) : on le sort de
/// l'isolation `MainActor` par défaut pour pouvoir l'appeler depuis n'importe
/// quel contexte (acteurs, closures concurrentes…) sans franchir le main actor.
public nonisolated enum MediaFormat {

    // Extensions qu'AVFoundation lit nativement (décodage matériel possible).
    static let avFoundationVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v"
    ]
    static let avFoundationAudioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "alac"
    ]

    // Formats vidéo qui nécessitent libVLC (AVPlayer échoue dessus).
    static let vlcVideoExtensions: Set<String> = [
        "mkv", "avi", "webm", "ts", "m2ts", "mts", "mpg", "mpeg", "flv",
        "wmv", "ogv", "3gp", "3g2", "divx", "vob", "asf", "rm", "rmvb",
        "f4v", "mxf", "m2v", "dav"
    ]
    // Formats audio qui nécessitent libVLC.
    static let vlcAudioExtensions: Set<String> = [
        "ogg", "oga", "opus", "wma", "ape", "dsf", "dff", "mka", "ac3",
        "dts", "amr", "tta", "wv"
    ]

    static func ext(_ name: String) -> String {
        (name as NSString).pathExtension.lowercased()
    }

    public static func isVideo(_ name: String) -> Bool {
        let e = ext(name)
        if avFoundationVideoExtensions.contains(e) || vlcVideoExtensions.contains(e) {
            return true
        }
        if let type = UTType(filenameExtension: e), type.conforms(to: .movie) {
            return true
        }
        return false
    }

    public static func isAudio(_ name: String) -> Bool {
        let e = ext(name)
        if avFoundationAudioExtensions.contains(e) || vlcAudioExtensions.contains(e) {
            return true
        }
        // Évite de classer une vidéo connue comme audio.
        if isVideo(name) { return false }
        if let type = UTType(filenameExtension: e), type.conforms(to: .audio) {
            return true
        }
        return false
    }

    public static func isMedia(_ name: String) -> Bool {
        isVideo(name) || isAudio(name)
    }

    // Formats image reconnus (vignettes de la galerie).
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp",
        "tiff", "tif", "jp2", "avif", "ico",
        // RAW courants (ImageIO sait en extraire une vignette)
        "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf", "srw"
    ]

    public static func isImage(_ name: String) -> Bool {
        let e = ext(name)
        if imageExtensions.contains(e) { return true }
        if let type = UTType(filenameExtension: e), type.conforms(to: .image) {
            return true
        }
        return false
    }

    /// Médias visuels = ce qui mérite une vignette dans la galerie.
    public static func isVisualMedia(_ name: String) -> Bool {
        isImage(name) || isVideo(name)
    }

    // Documents dont on sait rendre un aperçu (1re page). Pour l'instant PDF ;
    // extensible plus tard (pages, docx…) si un moteur de rendu est ajouté.
    static let documentExtensions: Set<String> = ["pdf"]

    /// Vrai pour un PDF (détection par extension, avec repli sur le type système).
    public static func isPDF(_ name: String) -> Bool {
        let e = ext(name)
        if documentExtensions.contains(e) { return true }
        if let type = UTType(filenameExtension: e), type.conforms(to: .pdf) {
            return true
        }
        return false
    }

    /// Fichiers éligibles à un aperçu « Remote Lens » (vignette + métadonnées
    /// par range requests) : images et PDF. La vidéo garde son chemin galerie.
    public static func hasLens(_ name: String) -> Bool {
        isImage(name) || isPDF(name)
    }

    /// Extensions de sous-titres « sidecar » qu'on cherche à côté du média.
    static let subtitleExtensions: Set<String> = [
        "srt", "ass", "ssa", "vtt", "sub", "idx"
    ]

    public static func isSubtitle(_ name: String) -> Bool {
        subtitleExtensions.contains(ext(name))
    }

    /// Moteur recommandé pour ce nom de fichier. Par défaut on penche vers
    /// VLC (le plus tolérant) pour les extensions inconnues afin d'éviter
    /// l'écran noir d'AVPlayer.
    public static func engine(for name: String) -> PlaybackEngine {
        let e = ext(name)
        if avFoundationVideoExtensions.contains(e) || avFoundationAudioExtensions.contains(e) {
            return .avFoundation
        }
        if vlcVideoExtensions.contains(e) || vlcAudioExtensions.contains(e) {
            return .vlc
        }
        // Extension inconnue : si le système la reconnaît comme un format
        // typiquement compatible AVFoundation, on tente AVPlayer ; sinon VLC.
        if let type = UTType(filenameExtension: e) {
            for compatible: UTType in [.mpeg4Movie, .quickTimeMovie, .mpeg4Audio, .mp3, .wav, .aiff] {
                if type.conforms(to: compatible) { return .avFoundation }
            }
        }
        return .vlc
    }
}
