//
//  MainTabView.swift
//  Rclone GUI — Views
//
//  Root container for the four primary surfaces: Home, Files, Transfers,
//  Settings. iOS uses a bottom TabView; macOS uses a native NavigationSplitView
//  sidebar (the iOS floating tab bar looks out of place in a Mac window).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MainTabView: View {
    @State private var selection: Tab
    // Explicit navigation path for the Files tab so a debug screenshot launch
    // (`--demo-screen folder`) can deep-link into a folder. Empty in normal use,
    // where NavigationLink(value:) drives the stack exactly as before.
    @State private var filesPath: [NavigationDestination] = []
    #if DEBUG
    @State private var demoCover: DemoCover?
    #endif

    init() {
        #if DEBUG
        let screen = DemoScreenArg.value
        switch screen {
        case "files", "folder": _selection = State(initialValue: .files)
        case "transfers":       _selection = State(initialValue: .transfers)
        case "settings":        _selection = State(initialValue: .settings)
        default:                _selection = State(initialValue: .home)
        }
        _filesPath = State(initialValue: screen == "folder"
            ? [.folder(remote: "iPhone", path: "Photos")]
            : [])
        let cover: DemoCover?
        switch screen {
        case "wizard":   cover = .wizard
        case "import":   cover = .importConfig
        case "photos":   cover = .photoSync
        case "security": cover = .security
        case "file":     cover = .fileDetail
        default:         cover = nil
        }
        _demoCover = State(initialValue: cover)
        #else
        _selection = State(initialValue: .home)
        #endif
    }

    enum Tab: Hashable, CaseIterable, Identifiable {
        case home
        case files
        case transfers
        case settings

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .home: return "Accueil"
            case .files: return "Fichiers"
            case .transfers: return "Transferts"
            case .settings: return "Réglages"
            }
        }

        var systemImage: String {
            switch self {
            case .home: return "house"
            case .files: return "folder"
            case .transfers: return "arrow.up.arrow.down.circle"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
            .navigationTitle("Rclone GUI")
        } detail: {
            NavigationStack {
                detailView(for: selection)
                    .navigationDestination(for: NavigationDestination.self, destination: navigationDestination)
            }
            // Reset the navigation stack when switching sections so a folder
            // pushed under Files doesn't bleed into Home/Transfers/Settings.
            .id(selection)
        }
        #else
        TabView(selection: $selection) {
            ForEach(Tab.allCases) { tab in
                tabStack(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
        }
        #if DEBUG
        // Debug-only deep link used by the App Store screenshot pipeline to land
        // directly on a given surface. Inert unless launched with `--demo-screen`.
        .fullScreenCover(item: $demoCover) { cover in
            NavigationStack { demoCoverView(cover) }
        }
        #endif
        #endif
    }

    @ViewBuilder
    private func tabStack(for tab: Tab) -> some View {
        if tab == .files {
            NavigationStack(path: $filesPath) {
                detailView(for: tab)
                    .navigationDestination(for: NavigationDestination.self, destination: navigationDestination)
            }
        } else {
            NavigationStack {
                detailView(for: tab)
                    .navigationDestination(for: NavigationDestination.self, destination: navigationDestination)
            }
        }
    }

    @ViewBuilder
    private func detailView(for tab: Tab) -> some View {
        switch tab {
        case .home: HomeView()
        case .files: FilesRootView()
        case .transfers: TransfersView()
        case .settings: SettingsView()
        }
    }

    @ViewBuilder
    private func navigationDestination(_ destination: NavigationDestination) -> some View {
        switch destination {
        case .folder(let remote, let path):
            FolderView(remote: remote, path: path)
        }
    }
}

#if DEBUG
/// Surfaces that the screenshot pipeline can present directly via a launch arg.
enum DemoCover: String, Identifiable {
    case wizard, importConfig, photoSync, security, fileDetail
    var id: String { rawValue }
}

/// Reads `--demo-screen <id>` from the process launch arguments.
enum DemoScreenArg {
    static var value: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo-screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

extension MainTabView {
    @ViewBuilder
    func demoCoverView(_ cover: DemoCover) -> some View {
        switch cover {
        case .wizard:       DemoWizardCatalog()
        case .importConfig: ImportConfigView(onImported: {})
        case .photoSync:    PhotoSyncSettingsView()
        case .security:     SecuritySettingsView()
        case .fileDetail:   FileDetailView(entry: Self.demoVideoEntry, remote: "iPhone", isInsideCrypt: false)
        }
    }

    static var demoVideoEntry: RemoteEntryDTO {
        RemoteEntryDTO(
            pathInRemote: "Vidéos/Vacances-Bali-2026.MOV",
            name: "Vacances-Bali-2026.MOV",
            isDirectory: false,
            size: 1_843_200_000,
            modTime: Date(),
            mimeType: "video/quicktime",
            hashMD5: "9f2c4e1ab7d83f0c5e6a1b2c3d4e5f60",
            hashSHA1: nil
        )
    }
}

/// Presents the real wizard backend catalog (`NameAndBackendView`) with a
/// pre-filled, valid remote name so the full "80+ services" list is visible,
/// then dismisses the auto-presented keyboard for a clean screenshot.
private struct DemoWizardCatalog: View {
    @State private var state: WizardState

    init() {
        let s = WizardState()
        s.name = "MonCloud"
        _state = State(initialValue: s)
    }

    var body: some View {
        NameAndBackendView(state: state, onNext: {})
            .navigationTitle("Nouveau remote")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    #if canImport(UIKit)
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                    #endif
                }
            }
    }
}
#endif

#Preview {
    MainTabView()
}
