//
//  AboutView.swift
//  Rclone GUI — Views/Settings
//

import SwiftUI

struct AboutView: View {
    @State private var rcloneVersion: String = "—"

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section("Versions") {
                LabeledContent("Rclone GUI", value: appVersion)
                LabeledContent("rclone (librclone)", value: rcloneVersion)
            }

            Section("Liens") {
                Link(destination: URL(string: "https://rclone.rougetet.com")!) {
                    Label("rclone.rougetet.com", systemImage: "globe")
                }
                Link(destination: URL(string: "https://github.com/VitalysRDT/rclone-gui-ios")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://rclone.org")!) {
                    Label("rclone.org", systemImage: "globe")
                }
                Link(destination: URL(string: "https://forum.rclone.org")!) {
                    Label("Forum communauté rclone", systemImage: "person.3")
                }
                Link(destination: URL(string: "https://github.com/rclone/rclone")!) {
                    Label("Code source rclone", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section("Crédits") {
                Text("Construit avec rclone et SwiftUI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("À propos")
        #if os(iOS)
        .rgInlineNavTitle()
        #endif
        .task {
            do {
                rcloneVersion = try await RcloneCore.shared.version()
            } catch {
                rcloneVersion = "ERR : \(error.localizedDescription)"
            }
        }
    }
}
