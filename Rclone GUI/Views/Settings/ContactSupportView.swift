//
//  ContactSupportView.swift
//  Rclone GUI — Views/Settings
//
//  Page « Contacter le développeur » : ouvre le client mail avec un
//  sujet pré-rempli (version + build + OS) pour que les rapports de
//  bug arrivent directement exploitables.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ContactSupportView: View {
    private static let supportEmail = "vitalys@rougetet.com"

    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        openMail()
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.blue)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Écrire un e-mail")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.primary)
                                Text(Self.supportEmail)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.rgGroupedRowBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button {
                        copyAddress()
                    } label: {
                        Label(copied ? String(localized: "Adresse copiée") : String(localized: "Copier l'adresse"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RG.accent)
                    .padding(.leading, 4)

                    Text("Le sujet inclut automatiquement la version de l'app pour accélérer le diagnostic. Réponse généralement sous quelques jours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.rgGroupedBackground)
        .navigationTitle("Contact")
        #if os(iOS)
        .rgInlineNavTitle()
        #endif
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(RG.accent.opacity(0.16))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(RG.accent)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("Contacter le développeur")
                    .font(.system(size: 20, weight: .bold))
                Text("Bug, idée de fonctionnalité ou question — chaque message est lu.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// Sujet : « Rclone GUI 1.3 (8) — iOS 27.0 » ; corps vide.
    static var mailtoURL: URL? {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        #if os(iOS)
        let os = "iOS \(UIDevice.current.systemVersion)"
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(v.majorVersion).\(v.minorVersion)"
        #endif
        let subject = "Rclone GUI \(version) (\(build)) — \(os)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url
    }

    private func openMail() {
        guard let url = Self.mailtoURL else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func copyAddress() {
        #if canImport(UIKit)
        UIPasteboard.general.string = Self.supportEmail
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.supportEmail, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

#Preview {
    NavigationStack { ContactSupportView() }
}
