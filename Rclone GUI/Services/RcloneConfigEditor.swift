//
//  RcloneConfigEditor.swift
//  Rclone GUI — Services
//
//  Local INI editor for rclone.conf. It intentionally preserves the core
//  rclone flow: the app stores the encrypted config, writes a plaintext
//  runtime copy, then lets RcloneCore read the same file as imported configs.
//

import Foundation

enum RcloneConfigEditor {
    struct RemoteConfigSnapshot: Sendable, Equatable {
        let name: String
        let type: String
        let options: [String: String]
    }

    enum ConfigError: LocalizedError, Equatable {
        case duplicateRemote(String)
        case remoteNotFound(String)
        case deletionFailed(String)
        case invalidRemoteName
        case invalidType
        case invalidOptionKey(String)
        case invalidUTF8

        var errorDescription: String? {
            switch self {
            case .duplicateRemote(let name):
                return String(localized: "Le remote « \(name) » existe déjà.")
            case .remoteNotFound(let name):
                return String(localized: "Le remote « \(name) » n’existe plus.")
            case .deletionFailed(let name):
                return String(localized: "Le remote « \(name) » est toujours présent après la suppression. Redémarre l’app puis réessaie ; si ça persiste, envoie les logs depuis Réglages → Logs.")
            case .invalidRemoteName:
                return String(localized: "Choisis un nom de remote sans :, [, ], / ni retour à la ligne.")
            case .invalidType:
                return String(localized: "Choisis un type rclone valide.")
            case .invalidOptionKey(let key):
                return String(localized: "L’option « \(key) » n’est pas valide.")
            case .invalidUTF8:
                return String(localized: "Le rclone.conf existant n’est pas lisible en UTF-8.")
            }
        }
    }

    static func addRemote(name: String, type: String, options: [String: String]) async throws {
        let existingData = try await ConfigStore.shared.load()
        let existingText: String
        if let existingData {
            guard let decoded = String(data: existingData, encoding: .utf8) else {
                throw ConfigError.invalidUTF8
            }
            existingText = decoded
        } else {
            existingText = ""
        }

        let updatedText = try updatedConfigText(
            existingText,
            addingRemoteNamed: name,
            type: type,
            options: options
        )
        try await ConfigStore.shared.save(Data(updatedText.utf8))
        try await ConfigStore.shared.migrateMasterKeyToSharedAccessGroupIfNeeded()
        await refreshRuntimeAndNotify()
    }

    /// Reads one remote section from the decrypted config without exposing
    /// the result to logs or UI. Sensitive values are returned only so the
    /// edit flow can distinguish an existing secret from a missing one.
    ///
    /// Deux sources coexistent et peuvent diverger : le store chiffré (ce que
    /// l'app persiste) et le rclone.conf runtime (ce que le moteur connaît, et
    /// ce que la liste des remotes affiche via `config/listremotes`). Le wizard
    /// écrit la section via `config/create` dès l'étape « Tester » et ne la
    /// re-chiffre dans le store qu'à la finalisation : un remote abandonné
    /// après un test raté n'existe donc que côté moteur. Lire le seul store
    /// faisait échouer l'édition d'un remote pourtant listé (« Impossible de
    /// charger le remote »). On retombe donc sur `config/dump`.
    static func remoteConfig(named name: String) async throws -> RemoteConfigSnapshot? {
        if let data = try await ConfigStore.shared.load() {
            guard let text = String(data: data, encoding: .utf8) else {
                throw ConfigError.invalidUTF8
            }
            if let stored = remoteConfig(in: text, named: name) {
                return stored
            }
        }
        return await engineRemoteConfig(named: name)
    }

    /// Reconstruit un snapshot depuis le `config/dump` du moteur. Utilisé quand
    /// la section n'est (pas encore) dans le store chiffré. Best-effort : un
    /// moteur indisponible renvoie `nil`, l'appelant traduira en
    /// `remoteNotFound`.
    static func engineRemoteConfig(named rawName: String) async -> RemoteConfigSnapshot? {
        let target = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty,
              let dump = try? await RcloneCore.shared.configDump(),
              let section = dump[target] else {
            return nil
        }
        return snapshot(fromDumpSection: section, named: target)
    }

    /// Traduit une section de `config/dump` en snapshot (pur, testable).
    static func snapshot(
        fromDumpSection section: [String: String],
        named name: String
    ) -> RemoteConfigSnapshot {
        var options = section
        let type = options.removeValue(forKey: "type") ?? "unknown"
        return RemoteConfigSnapshot(name: name, type: type, options: options)
    }

    static func remoteConfig(in text: String, named rawName: String) -> RemoteConfigSnapshot? {
        let target = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        var currentName: String?
        var currentType = "unknown"
        var currentOptions: [String: String] = [:]
        var found: RemoteConfigSnapshot?

        func flush() {
            guard found == nil, currentName == target else { return }
            found = RemoteConfigSnapshot(
                name: target,
                type: currentType,
                options: currentOptions
            )
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), let close = line.firstIndex(of: "]"), close > line.startIndex {
                flush()
                currentName = String(line[line.index(after: line.startIndex)..<close])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                currentType = "unknown"
                currentOptions = [:]
                continue
            }

            guard currentName == target,
                  !line.isEmpty,
                  !line.hasPrefix("#"),
                  !line.hasPrefix(";"),
                  let equal = line.firstIndex(of: "=") else { continue }
            let key = line[..<equal].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            if key == "type" {
                currentType = value
            } else if !key.isEmpty {
                currentOptions[String(key)] = String(value)
            }
        }
        flush()
        return found
    }

    /// Updates an existing remote through rclone's native config/update RPC.
    /// Empty values are omitted so existing secrets (passwords or tokens) stay
    /// intact until the user explicitly enters a replacement. rclone handles
    /// password obfuscation and any backend-specific update questions.
    @MainActor
    static func updateRemote(
        name: String,
        type: String,
        options: [String: String],
        obscure: Bool,
        ask: @escaping (_ option: RcloneOptionSchema, _ lastError: String?) async -> String?
    ) async throws {
        let parameters = try normalizedOptions(options).reduce(into: [String: String]()) { result, item in
            result[item.key] = item.value
        }
        let flow = ConfigCreateFlow(rpc: { method, input in
            try await RcloneCore.shared.rpc(method, input: input)
        })
        try await flow.run(
            name: name,
            type: type,
            parameters: parameters,
            obscure: obscure,
            initialMethod: "config/update",
            ask: ask
        )
        try await ConfigStore.shared.persistRuntimeConfigToStore()
        await refreshRuntimeAndNotify()
    }

    /// Supprime un remote de rclone.conf (retire la section `[name]` et son
    /// corps), réécrit le store chiffré, puis recharge le moteur et le
    /// manifest FileProvider. Les données distantes ne sont pas touchées.
    ///
    /// La suppression est menée des DEUX côtés, puis vérifiée :
    ///
    /// 1. store chiffré — la section est retirée du texte INI persisté ;
    /// 2. moteur — `config/delete` retire la même section du rclone.conf
    ///    runtime, seul endroit où vit un remote écrit par `config/create`
    ///    mais jamais finalisé (test de connexion raté puis wizard fermé) ;
    /// 3. vérification — si le nom survit au listing, on lève.
    ///
    /// Signalé en 2.1 : un remote dans cet état revenait après chaque tentative
    /// de suppression, sans erreur ni ligne de log (le store n'ayant pas la
    /// section, le retrait était un no-op et l'ancien code rendait la main en
    /// silence — voire sortait avant même de recharger quand aucun store
    /// n'existait encore).
    static func deleteRemote(name: String) async throws {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { throw ConfigError.invalidRemoteName }

        if let existingData = try await ConfigStore.shared.load(),
           let existingText = String(data: existingData, encoding: .utf8) {
            let updatedText = configText(existingText, removingSectionNamed: target)
            try await ConfigStore.shared.save(Data(updatedText.utf8))
        }

        struct DeleteInput: Encodable { let name: String }
        if let payload = try? JSONEncoder().encode(DeleteInput(name: target)),
           let json = String(data: payload, encoding: .utf8) {
            do {
                _ = try await RcloneCore.shared.rpcRaw("config/delete", json)
            } catch {
                // Un remote absent du runtime fait échouer config/delete : ce
                // n'est pas fatal, l'étape 3 tranche.
                await LogService.shared.log(
                    .debug,
                    category: "config",
                    message: "config/delete « \(target) » : \(error.localizedDescription)"
                )
            }
        }

        await refreshRuntimeAndNotify()

        let remaining = (try? await RcloneCore.shared.listRemoteNames()) ?? []
        guard !remaining.contains(target) else {
            await LogService.shared.log(
                .error,
                category: "config",
                message: "Remote « \(target) » toujours listé après suppression"
            )
            throw ConfigError.deletionFailed(target)
        }
        await LogService.shared.log(
            .info,
            category: "config",
            message: "Remote « \(target) » supprimé de la configuration"
        )
    }

    /// Retourne le texte INI privé de la section `[rawName]` (en-tête + lignes
    /// jusqu'à la prochaine section ou la fin du fichier).
    static func configText(_ text: String, removingSectionNamed rawName: String) -> String {
        let target = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String] = []
        var skipping = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), let close = line.firstIndex(of: "]"), close > line.startIndex {
                let sectionName = line[line.index(after: line.startIndex)..<close]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                skipping = (sectionName == target)
                if skipping { continue }
            }
            if !skipping {
                result.append(String(rawLine))
            }
        }
        return result.joined(separator: "\n")
    }

    static func refreshRuntimeAndNotify() async {
        do {
            try await RcloneCore.shared.reloadConfigurationFromStore()
        } catch {
            await RcloneCore.shared.invalidateConfigCache()
            await LogService.shared.log(
                .error,
                category: "config",
                message: "Rechargement rclone impossible : \(error.localizedDescription)"
            )
        }

        do {
            let remotes = try await RemoteService.shared.listRemoteSummaries()
            await FileProviderManager.shared.writeRemotesManifest(remotes)
        } catch {
            await LogService.shared.log(
                .error,
                category: "fileprovider",
                message: "Manifest FileProvider non rafraîchi après changement de config : \(error.localizedDescription)"
            )
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .rcloneConfigurationDidChange, object: nil)
        }
    }

    static func updatedConfigText(
        _ text: String,
        addingRemoteNamed rawName: String,
        type rawType: String,
        options rawOptions: [String: String]
    ) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidRemoteName(name) else {
            throw ConfigError.invalidRemoteName
        }

        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidOptionValue(type) else {
            throw ConfigError.invalidType
        }

        if sectionNames(in: text).contains(name) {
            throw ConfigError.duplicateRemote(name)
        }

        let options = try normalizedOptions(rawOptions)
        let rendered = renderSection(name: name, type: type, options: options)

        guard !text.isEmpty else {
            return rendered + "\n"
        }

        var updated = text
        if !updated.hasSuffix("\n") {
            updated.append("\n")
        }
        updated.append("\n")
        updated.append(rendered)
        updated.append("\n")
        return updated
    }

    static func sectionNames(in text: String) -> Set<String> {
        var names = Set<String>()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["),
                  let close = line.firstIndex(of: "]"),
                  close > line.startIndex else {
                continue
            }
            let name = line[line.index(after: line.startIndex)..<close]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                names.insert(name)
            }
        }
        return names
    }

    private static func normalizedOptions(_ rawOptions: [String: String]) throws -> [(key: String, value: String)] {
        var options: [(key: String, value: String)] = []
        for (rawKey, rawValue) in rawOptions {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty, key != "type" else { continue }
            guard isValidOptionKey(key), isValidOptionValue(value) else {
                throw ConfigError.invalidOptionKey(key.isEmpty ? rawKey : key)
            }
            options.append((key, value))
        }
        return options.sorted { lhs, rhs in
            lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }
    }

    private static func renderSection(name: String, type: String, options: [(key: String, value: String)]) -> String {
        var lines = ["[\(name)]", "type = \(type)"]
        for option in options {
            lines.append("\(option.key) = \(option.value)")
        }
        return lines.joined(separator: "\n")
    }

    private static func isValidRemoteName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let invalid = CharacterSet(charactersIn: ":[]/\\\n\r")
        return name.rangeOfCharacter(from: invalid) == nil
    }

    private static func isValidOptionKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        let invalid = CharacterSet(charactersIn: "=[]\n\r")
        return key.rangeOfCharacter(from: invalid) == nil
    }

    private static func isValidOptionValue(_ value: String) -> Bool {
        !value.isEmpty && value.rangeOfCharacter(from: CharacterSet(charactersIn: "\n\r")) == nil
    }
}
