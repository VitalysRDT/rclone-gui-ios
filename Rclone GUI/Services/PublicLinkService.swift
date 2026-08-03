//
//  PublicLinkService.swift
//  Rclone GUI — Services
//
//  Pure formatting and per-remote persistence for public/CDN links. Custom
//  domains are intentionally kept out of rclone.conf: they are presentation
//  preferences, not backend credentials, and an unknown rclone option could
//  make an otherwise valid remote unusable.
//

import Foundation

enum PublicLinkFormatter {
    /// Accepts either a full HTTP(S) URL or a bare domain. The normalized URL
    /// never contains credentials, a query, or a fragment, and has no trailing
    /// slash (except for the origin root).
    static func normalizedBaseURL(from rawValue: String) -> URL? {
        var candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else {
            return nil
        }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url
    }

    /// Builds `<custom origin>/<remote path>` while encoding each object-name
    /// segment independently. Encoding per segment preserves `/` as the folder
    /// separator and safely handles spaces, `#`, `%`, `?`, and Unicode names.
    static func customURL(baseURL: URL, remotePath: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        let encodedRemotePath = remotePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: allowed) }
            .joined(separator: "/")

        let basePath = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: "/")
        let joinedPath = [basePath, encodedRemotePath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.percentEncodedPath = joinedPath.isEmpty ? "/" : "/\(joinedPath)"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func markdown(url: URL, name: String, isDirectory: Bool) -> String {
        let escapedName = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        if !isDirectory && MediaFormat.isImage(name) {
            return "![\(escapedName)](\(url.absoluteString))"
        }
        return "[\(escapedName)](\(url.absoluteString))"
    }

    static func html(url: URL, name: String, isDirectory: Bool) -> String {
        let escapedName = htmlEscaped(name)
        let escapedURL = htmlEscaped(url.absoluteString)
        if !isDirectory && MediaFormat.isImage(name) {
            return "<img src=\"\(escapedURL)\" alt=\"\(escapedName)\">"
        }
        return "<a href=\"\(escapedURL)\">\(escapedName)</a>"
    }

    /// Escapes text for both HTML element content and quoted attribute values.
    /// Escaping quotes as well as markup characters keeps file names and URLs
    /// from terminating an attribute or injecting additional HTML.
    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

enum RemotePublicLinkSettingsStore {
    private static let defaultsKey = "publicLinks.customBaseURLByRemote.v1"

    static func customBaseURL(for remote: String, defaults: UserDefaults = .standard) -> String {
        storedValues(defaults: defaults)[remote] ?? ""
    }

    @discardableResult
    static func setCustomBaseURL(
        _ rawValue: String,
        for remote: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        var values = storedValues(defaults: defaults)
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            values.removeValue(forKey: remote)
            defaults.set(values, forKey: defaultsKey)
            return ""
        }
        guard let normalized = PublicLinkFormatter.normalizedBaseURL(from: trimmed) else {
            return nil
        }
        let stored = normalized.absoluteString
        values[remote] = stored
        defaults.set(values, forKey: defaultsKey)
        return stored
    }

    private static func storedValues(defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
}
