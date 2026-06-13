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
    enum ConfigError: LocalizedError, Equatable {
        case duplicateRemote(String)
        case invalidRemoteName
        case invalidType
        case invalidOptionKey(String)
        case invalidUTF8

        var errorDescription: String? {
            switch self {
            case .duplicateRemote(let name):
                return String(localized: "Le remote « \(name) » existe déjà.")
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

    /// Supprime un remote de rclone.conf (retire la section `[name]` et son
    /// corps), réécrit le store chiffré, puis recharge le moteur et le
    /// manifest FileProvider. Les données distantes ne sont pas touchées.
    static func deleteRemote(name: String) async throws {
        let existingData = try await ConfigStore.shared.load()
        guard let existingData,
              let existingText = String(data: existingData, encoding: .utf8) else {
            // Pas de config → rien à supprimer.
            return
        }
        let updatedText = configText(existingText, removingSectionNamed: name)
        try await ConfigStore.shared.save(Data(updatedText.utf8))
        await refreshRuntimeAndNotify()
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
