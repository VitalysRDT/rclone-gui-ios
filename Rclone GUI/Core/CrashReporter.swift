//
//  CrashReporter.swift
//  Rclone GUI — Core
//
//  Capture des crashs pour rapport au développeur. Trois mécanismes
//  complémentaires, car le crash le plus fréquent (échec de refresh OAuth
//  → librclone `log.Fatal` → `os.Exit`) n'est PAS rattrapable par un handler
//  Swift : c'est une sortie « propre » du process, sans signal ni exception.
//
//   1. Redirection de `stderr` vers un fichier de l'App Group : librclone écrit
//      son message fatal sur stderr juste avant `os.Exit`, donc on le capture.
//   2. Handlers NSException + signaux (SIGSEGV/SIGABRT/…) : crashs Swift/natifs.
//      Le handler de signal n'utilise QUE des primitives async-signal-safe
//      (backtrace_symbols_fd, write, fsync) sur des buffers pré-alloués.
//   3. Marqueur de session : créé à l'ouverture, supprimé au passage en
//      arrière-plan. S'il est encore présent au lancement suivant, la session
//      précédente s'est terminée en avant-plan sans transition propre → crash.
//
//  Au lancement, si la session précédente a mal fini, on consolide un rapport
//  texte (cause + tail stderr + versions) que l'UI (écran Logs) propose
//  d'envoyer par e-mail / partage.
//

import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Globals async-signal-safe (pré-alloués à l'install)

/// Descripteur du fichier de crash, ouvert une fois à l'install. Le handler de
/// signal n'écrit que via ce fd (pas d'allocation Swift dans le handler).
private nonisolated(unsafe) var crashReportFD: Int32 = -1
private let crashFrameCapacity: Int32 = 64
private nonisolated(unsafe) var crashFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>? = nil

private func crashSignalHandler(_ sig: Int32) {
    if crashReportFD >= 0, let frames = crashFrames {
        let header = "\n=== CRASH (signal \(sig)) ===\n"
        _ = header.withCString { write(crashReportFD, $0, strlen($0)) }
        let n = backtrace(frames, crashFrameCapacity)
        backtrace_symbols_fd(frames, n, crashReportFD)
        fsync(crashReportFD)
    }
    // Rétablit le handler par défaut et re-déclenche pour produire le crash
    // report système habituel.
    signal(sig, SIG_DFL)
    raise(sig)
}

public enum CrashReporter {

    private static var dir: URL {
        AppGroup.containerURL.appending(path: "diagnostics", directoryHint: .isDirectory)
    }
    /// stderr de la session EN COURS (librclone + NSLog y écrivent).
    private static var stderrURL: URL { dir.appending(path: "stderr.log") }
    /// stderr de la session PRÉCÉDENTE (archivé au lancement).
    private static var stderrPrevURL: URL { dir.appending(path: "stderr-prev.log") }
    /// Crash natif/exception écrit par les handlers.
    private static var crashURL: URL { dir.appending(path: "last-crash.txt") }
    /// Marqueur « une session est en avant-plan ».
    private static var sessionMarkerURL: URL { dir.appending(path: "session.active") }
    /// Rapport consolidé proposé à l'utilisateur au prochain lancement.
    private static var pendingReportURL: URL { dir.appending(path: "pending-report.txt") }

    private static let maxStderrTail = 64 * 1024  // 64 Ko de queue suffisent.

    // MARK: - Installation

    /// À appeler en TOUT PREMIER au lancement, avant d'initialiser librclone.
    public static func install() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // 1. La session précédente a-t-elle mal fini ? On consolide AVANT de
        //    réinitialiser les fichiers.
        consolidatePreviousSessionIfCrashed()

        // 2. Archive le stderr de la session précédente puis repart sur un
        //    fichier neuf, et redirige stderr dedans.
        try? fm.removeItem(at: stderrPrevURL)
        try? fm.moveItem(at: stderrURL, to: stderrPrevURL)
        redirectStderr()

        // 3. Handlers natifs.
        crashFrames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: Int(crashFrameCapacity))
        let crashFD = open(crashURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if crashFD >= 0 { crashReportFD = crashFD }
        installHandlers()

        // 4. Arme la session courante.
        armSession()
    }

    /// Recrée le marqueur de session (retour en avant-plan).
    public static func armSession() {
        FileManager.default.createFile(atPath: sessionMarkerURL.path, contents: Data())
    }

    /// Supprime le marqueur — sortie propre (passage en arrière-plan / terminaison).
    public static func markCleanExit() {
        try? FileManager.default.removeItem(at: sessionMarkerURL)
    }

    // MARK: - Rapport en attente (lu par l'UI)

    /// URL d'un fichier texte de rapport si la session précédente a crashé.
    public static func pendingReportFileURL() -> URL? {
        FileManager.default.fileExists(atPath: pendingReportURL.path) ? pendingReportURL : nil
    }

    public static func pendingReportText() -> String? {
        guard let url = pendingReportFileURL() else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Marque le rapport comme traité (l'utilisateur l'a envoyé ou ignoré).
    public static func clearPendingReport() {
        try? FileManager.default.removeItem(at: pendingReportURL)
    }

    // MARK: - Implémentation

    private static func consolidatePreviousSessionIfCrashed() {
        let fm = FileManager.default
        let crashText = (try? String(contentsOf: crashURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hadCrashFile = !(crashText ?? "").isEmpty
        let markerExisted = fm.fileExists(atPath: sessionMarkerURL.path)

        // Nettoyage du marqueur quoi qu'il arrive (on réarmera après).
        defer { try? fm.removeItem(at: sessionMarkerURL) }

        guard hadCrashFile || markerExisted else {
            // Sortie propre la dernière fois → pas de rapport. On purge un
            // éventuel crash file vide.
            try? fm.removeItem(at: crashURL)
            return
        }

        // Date approximative du crash = mtime du marqueur (≈ dernier lancement).
        let when = (try? fm.attributesOfItem(atPath: sessionMarkerURL.path)[.modificationDate] as? Date) ?? nil
        let formatter = ISO8601DateFormatter()
        let whenText = when.map { formatter.string(from: $0) } ?? "inconnue"

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        #if os(iOS)
        let osText = "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #else
        let osText = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #endif

        var report = """
        Rclone GUI — Rapport de crash
        =============================
        App        : \(version) (\(build))
        Système    : \(osText)
        Date (≈)   : \(whenText)
        Type       : \(hadCrashFile ? "crash natif / exception (signal)" : "sortie inattendue (probable fatal moteur rclone / OOM)")

        """

        if hadCrashFile, let crashText {
            report += "\n--- Backtrace ---\n\(crashText)\n"
        }

        // Queue du stderr de la session précédente (contient le message fatal
        // de librclone le cas échéant — c'est la pièce maîtresse pour le bug
        // « refresh token expiré »).
        if let tail = tailOfFile(at: stderrURL, maxBytes: maxStderrTail), !tail.isEmpty {
            report += "\n--- Sortie moteur (stderr, fin) ---\n\(tail)\n"
        }

        try? report.data(using: .utf8)?.write(to: pendingReportURL, options: [.atomic])
        // On consomme le crash file (déjà intégré au rapport).
        try? fm.removeItem(at: crashURL)
    }

    private static func redirectStderr() {
        let fd = open(stderrURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        dup2(fd, STDERR_FILENO)
        close(fd)
        // Non-bufferisé : le message fatal doit atteindre le disque avant os.Exit.
        setvbuf(stderr, nil, _IONBF, 0)
    }

    private static func installHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            let text = """
            === CRASH (NSException) ===
            name   : \(exception.name.rawValue)
            reason : \(exception.reason ?? "—")

            \(stack)
            """
            try? text.data(using: .utf8)?.write(to: CrashReporter.crashURL, options: [.atomic])
        }

        for sig in [SIGABRT, SIGSEGV, SIGILL, SIGTRAP, SIGBUS, SIGFPE] {
            signal(sig, crashSignalHandler)
        }
    }

    /// Lit au plus `maxBytes` octets en fin de fichier (sans charger tout le fichier).
    private static func tailOfFile(at url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
