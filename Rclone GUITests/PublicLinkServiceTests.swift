//
//  PublicLinkServiceTests.swift
//  Rclone GUITests
//

import Foundation
import Testing
@testable import Rclone_GUI

@Suite("Public links and custom CDN domains")
struct PublicLinkServiceTests {
    @Test("A bare domain is normalized to HTTPS")
    func normalizesBareDomain() throws {
        let url = try #require(PublicLinkFormatter.normalizedBaseURL(from: " img.example.com/ "))
        #expect(url.absoluteString == "https://img.example.com/")
    }

    @Test("Credentials and non-HTTP schemes are rejected")
    func rejectsUnsafeBaseURLs() {
        #expect(PublicLinkFormatter.normalizedBaseURL(from: "ftp://img.example.com") == nil)
        #expect(PublicLinkFormatter.normalizedBaseURL(from: "https://user:pass@img.example.com") == nil)
    }

    @Test("CDN paths preserve folders and encode object names")
    func buildsEncodedCDNURL() throws {
        let base = try #require(PublicLinkFormatter.normalizedBaseURL(from: "https://cdn.example.com/images"))
        let url = try #require(PublicLinkFormatter.customURL(
            baseURL: base,
            remotePath: "articles/été 2026/photo #1%.png"
        ))
        #expect(
            url.absoluteString
                == "https://cdn.example.com/images/articles/%C3%A9t%C3%A9%202026/photo%20%231%25.png"
        )
    }

    @Test("CDN paths can remove a matching bucket prefix")
    func removesMatchingPathPrefix() throws {
        let base = try #require(PublicLinkFormatter.normalizedBaseURL(from: "https://image.example.com"))
        let url = try #require(PublicLinkFormatter.customURL(
            baseURL: base,
            remotePath: "aab/img/CloudX_1785625479.452707.jpg",
            removingPathPrefix: "/aab/"
        ))
        #expect(url.absoluteString == "https://image.example.com/img/CloudX_1785625479.452707.jpg")

        let unchanged = try #require(PublicLinkFormatter.customURL(
            baseURL: base,
            remotePath: "aab2/img/photo.jpg",
            removingPathPrefix: "aab"
        ))
        #expect(unchanged.absoluteString == "https://image.example.com/aab2/img/photo.jpg")
    }

    @Test("Path prefixes are normalized without changing their components")
    func normalizesPathPrefix() {
        #expect(PublicLinkFormatter.normalizedPathPrefix(from: " /aab//img/ ") == "aab/img")
        #expect(PublicLinkFormatter.normalizedPathPrefix(from: "   ").isEmpty)
    }

    @Test("Images use Markdown image syntax")
    func formatsImageMarkdown() throws {
        let url = try #require(URL(string: "https://img.example.com/photo.png"))
        let markdown = PublicLinkFormatter.markdown(
            url: url,
            name: "photo [été].png",
            isDirectory: false
        )
        #expect(markdown == "![photo \\[été\\].png](https://img.example.com/photo.png)")
    }

    @Test("Image HTML escapes alt text and URL attributes")
    func formatsEscapedImageHTML() throws {
        let url = try #require(URL(string: "https://img.example.com/photo.png?size=large&download=1"))
        let html = PublicLinkFormatter.html(
            url: url,
            name: "photo <été> & \"amis\" '2026'.png",
            isDirectory: false
        )
        #expect(
            html
                == "<img src=\"https://img.example.com/photo.png?size=large&amp;download=1\" alt=\"photo &lt;été&gt; &amp; &quot;amis&quot; &#39;2026&#39;.png\">"
        )
    }

    @Test("Non-images use escaped HTML links")
    func formatsEscapedHTMLLink() throws {
        let url = try #require(URL(string: "https://cdn.example.com/files/guide.pdf?from=docs&lang=fr"))
        let html = PublicLinkFormatter.html(
            url: url,
            name: "Guide <Docusaurus> & nouveautés.pdf",
            isDirectory: false
        )
        #expect(
            html
                == "<a href=\"https://cdn.example.com/files/guide.pdf?from=docs&amp;lang=fr\">Guide &lt;Docusaurus&gt; &amp; nouveautés.pdf</a>"
        )
    }

    @Test("A custom domain is persisted per remote")
    func persistsPerRemote() throws {
        let suiteName = "PublicLinkServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let stored = RemotePublicLinkSettingsStore.setCustomBaseURL(
            "cdn.example.com/root/",
            for: "photos",
            defaults: defaults
        )
        #expect(stored == "https://cdn.example.com/root")
        #expect(
            RemotePublicLinkSettingsStore.customBaseURL(for: "photos", defaults: defaults)
                == "https://cdn.example.com/root"
        )
        #expect(RemotePublicLinkSettingsStore.customBaseURL(for: "other", defaults: defaults).isEmpty)

        let prefix = RemotePublicLinkSettingsStore.setPathPrefixToRemove(
            "/aab/",
            for: "photos",
            defaults: defaults
        )
        #expect(prefix == "aab")
        #expect(
            RemotePublicLinkSettingsStore.pathPrefixToRemove(for: "photos", defaults: defaults)
                == "aab"
        )
        #expect(RemotePublicLinkSettingsStore.pathPrefixToRemove(for: "other", defaults: defaults).isEmpty)
    }
}
