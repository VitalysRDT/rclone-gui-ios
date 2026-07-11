//
//  RemoteLensPlan.swift
//  Rclone GUI — Core
//
//  Logique PURE de la feature « Remote Lens » (aperçus par range requests) :
//  décision de stratégie de lecture (combien d'octets rapatrier) et formatage
//  des métadonnées EXIF. Aucune I/O, aucun UIKit → 100 % testable sans réseau
//  ni fichier. Le service `RemoteLensService` consomme ces décisions.
//

import Foundation

public nonisolated enum RemoteLensPlan {

    // MARK: - Stratégie de lecture

    /// Comment rapatrier les octets d'un fichier distant pour son aperçu.
    public enum FetchStrategy: Equatable, Sendable {
        /// Fichier assez petit : GET complet borné (le transport reste range-capable,
        /// mais on tire tout l'objet).
        case fullBounded
        /// Lire seulement les `N` premiers octets, puis tenter un décodage incrémental
        /// (vignette EXIF embarquée + métadonnées, souvent en tête de fichier).
        case headRange(Int64)
        /// Accès aléatoire par plages piloté par le consommateur (PDF : xref en fin +
        /// objets de la 1re page) — quelle que soit la taille.
        case randomAccess
        /// Trop volumineux pour un aperçu raisonnable → icône de repli.
        case skip
    }

    // Aligné sur `ThumbnailService.imageSizeCap` (80 Mo) : au-delà, pas de vignette.
    public static let imageFullCap: Int64 = 80 * 1024 * 1024
    // Fenêtre de tête pour EXIF + vignette embarquée (JPEG/HEIC/RAW la placent tôt).
    public static let imageHeadWindow: Int64 = 512 * 1024
    // En dessous de ce seuil, un GET complet borné est plus simple qu'un range de tête.
    public static let imageInlineCap: Int64 = 256 * 1024

    /// Stratégie pour une image selon sa taille.
    /// - `size <= 0` (inconnue) → tenter la fenêtre de tête.
    public static func imageStrategy(size: Int64) -> FetchStrategy {
        if size > imageFullCap { return .skip }
        if size > 0, size <= imageInlineCap { return .fullBounded }
        return .headRange(imageHeadWindow)
    }

    /// Stratégie pour un PDF : toujours l'accès aléatoire (lecture ciblée xref +
    /// 1re page), sans plafond de taille.
    public static func pdfStrategy(size: Int64) -> FetchStrategy {
        .randomAccess
    }

    // MARK: - Arithmétique de plage

    /// Plage `[start, start+window-1]` bornée à l'octet final du fichier, pour ne
    /// jamais déclencher un `416 Range Not Satisfiable`.
    /// - Retourne `nil` si `start` est hors du fichier (≥ taille) ou paramètres invalides.
    public static func clampedRange(start: Int64, window: Int64, totalSize: Int64) -> ClosedRange<Int64>? {
        guard window > 0, start >= 0 else { return nil }
        // Taille inconnue : on fait confiance à la fenêtre demandée.
        if totalSize <= 0 {
            return start...(start + window - 1)
        }
        guard start < totalSize else { return nil }
        let end = min(start + window - 1, totalSize - 1)
        return start...end
    }

    // MARK: - Formatage EXIF (pur)

    /// Temps de pose : « 1/250 s » sous 1 s, « 2 s » au-dessus.
    public static func formatExposureTime(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds >= 1 {
            // Retire un « .0 » superflu.
            let rounded = (seconds * 10).rounded() / 10
            let s = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
            return "\(s) s"
        }
        let denom = Int((1.0 / seconds).rounded())
        return "1/\(denom) s"
    }

    /// Ouverture : « f/2.8 ».
    public static func formatFNumber(_ f: Double) -> String {
        guard f > 0 else { return "—" }
        let rounded = (f * 10).rounded() / 10
        let s = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return "f/\(s)"
    }

    /// Focale : « 50 mm ».
    public static func formatFocalLength(_ mm: Double) -> String {
        guard mm > 0 else { return "—" }
        return "\(Int(mm.rounded())) mm"
    }

    /// Sensibilité : « ISO 100 ».
    public static func formatISO(_ iso: Int) -> String {
        guard iso > 0 else { return "—" }
        return "ISO \(iso)"
    }

    /// Applique le signe hémisphère (réf « S » ou « W » → valeur négative).
    public static func gpsDecimal(_ value: Double, ref: String?) -> Double {
        guard let ref = ref?.uppercased() else { return value }
        return (ref == "S" || ref == "W") ? -abs(value) : abs(value)
    }

    /// Coordonnées lisibles : « 48.8566, 2.3522 » (déjà signées).
    public static func formatCoordinate(lat: Double, lon: Double) -> String {
        String(format: "%.5f, %.5f", lat, lon)
    }
}
