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

    /// Normalizes a logical remote path prefix such as `/aab/` to `aab`.
    /// Empty components are ignored so users can paste either a bucket name or
    /// a bucket-relative prefix without having to format the slashes exactly.
    static func normalizedPathPrefix(from rawValue: String) -> String {
        pathComponents(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
            .joined(separator: "/")
    }

    /// Builds `<custom origin>/<remote path>` while encoding each object-name
    /// segment independently. Encoding per segment preserves `/` as the folder
    /// separator and safely handles spaces, `#`, `%`, `?`, and Unicode names.
    /// An optional prefix is removed only when it matches the first path
    /// components exactly. This supports S3-compatible providers such as
    /// Qiniu Kodo, whose object paths can include the bucket name.
    static func customURL(
        baseURL: URL,
        remotePath: String,
        removingPathPrefix: String? = nil
    ) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let effectiveRemotePath = pathByRemovingPrefix(removingPathPrefix, from: remotePath)

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        let encodedRemotePath = pathComponents(effectiveRemotePath)
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

    private static func pathByRemovingPrefix(_ prefix: String?, from remotePath: String) -> String {
        let prefixComponents = pathComponents(prefix ?? "")
        guard !prefixComponents.isEmpty else { return remotePath }

        let remoteComponents = pathComponents(remotePath)
        guard remoteComponents.count >= prefixComponents.count,
              Array(remoteComponents.prefix(prefixComponents.count)) == prefixComponents else {
            return remotePath
        }
        return remoteComponents.dropFirst(prefixComponents.count).joined(separator: "/")
    }

    private static func pathComponents(_ value: String) -> [String] {
        value
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
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
    private static let pathPrefixDefaultsKey = "publicLinks.pathPrefixToRemoveByRemote.v1"

    static func customBaseURL(for remote: String, defaults: UserDefaults = .standard) -> String {
        storedValues(defaults: defaults)[remote] ?? ""
    }

    static func pathPrefixToRemove(for remote: String, defaults: UserDefaults = .standard) -> String {
        pathPrefixValues(defaults: defaults)[remote] ?? ""
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

    @discardableResult
    static func setPathPrefixToRemove(
        _ rawValue: String,
        for remote: String,
        defaults: UserDefaults = .standard
    ) -> String {
        var values = pathPrefixValues(defaults: defaults)
        let normalized = PublicLinkFormatter.normalizedPathPrefix(from: rawValue)
        if normalized.isEmpty {
            values.removeValue(forKey: remote)
        } else {
            values[remote] = normalized
        }
        defaults.set(values, forKey: pathPrefixDefaultsKey)
        return normalized
    }

    private static func storedValues(defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    private static func pathPrefixValues(defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: pathPrefixDefaultsKey) as? [String: String] ?? [:]
    }
}
