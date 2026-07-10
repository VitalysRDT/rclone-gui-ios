//
//  HandoffLandingView.swift
//  Rclone GUI — Views/Settings/Handoff
//
//  Point d'entrée du flux Handoff P2P (RG-16 / RG-4) :
//  propose d'envoyer ou de recevoir une config chiffrée entre appareils
//  sans serveur. Le transport (QR code, AirDrop, presse-papiers,
//  fichier .rclonebackup) est sélectionné à la seconde étape, le
//  chiffrement (ChaCha20-Poly1305, passphrase Diceware 6 mots hors
//  canal) reste identique.
//

import SwiftUI

struct HandoffLandingView: View {
    var body: some View {
        Form {
            heroSection
            actionsSection
            explainerSection
        }
        .navigationTitle("Handoff P2P")
        #if os(iOS)
        .rgInlineNavTitle()
        #endif
    }

    private var heroSection: some View {
        Section {
            AppHeroCard(
                title: "Handoff P2P",
                subtitle: "Transfère une config chiffrée entre appareils via QR ou AirDrop. Sans serveur.",
                systemImage: "iphone.and.arrow.forward",
                tint: .purple
            ) {
                HStack(spacing: 10) {
                    AppMetricPill(
                        value: "E2E",
                        label: "chiffré",
                        systemImage: "lock.fill",
                        tint: .green
                    )
                    AppMetricPill(
                        value: "0",
                        label: "serveur",
                        systemImage: "xmark.icloud.fill",
                        tint: .indigo
                    )
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var actionsSection: some View {
        Section {
            NavigationLink {
                HandoffSendView()
            } label: {
                HandoffNavigationRow(
                    icon: "arrow.up.doc.fill",
                    title: "Envoyer ma config",
                    subtitle: "Vers un autre iPhone, Mac ou iPad",
                    tint: .purple,
                    showsChevron: false
                )
            }

            NavigationLink {
                HandoffReceiveView()
            } label: {
                HandoffNavigationRow(
                    icon: "arrow.down.doc.fill",
                    title: "Recevoir une config",
                    subtitle: "Depuis un QR, AirDrop ou un fichier",
                    tint: .blue,
                    showsChevron: false
                )
            }
        } header: {
            Text("Choisis une direction")
        }
    }

    private var explainerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                row(
                    systemImage: "lock.shield.fill",
                    tint: .green,
                    title: "Chiffrement de bout en bout",
                    body: "Ton rclone.conf est chiffré (ChaCha20-Poly1305) avec une clé dérivée d'une passphrase de 6 mots avant de quitter l'appareil. Personne ne peut le lire sans la passphrase."
                )
                row(
                    systemImage: "person.fill.questionmark",
                    tint: .purple,
                    title: "Aucun serveur",
                    body: "Pas de backend, pas de compte, pas de cloud. Le blob voyage directement d'un appareil à l'autre via QR (visuel), AirDrop (Bluetooth/Wi-Fi local) ou fichier."
                )
                row(
                    systemImage: "key.horizontal.fill",
                    tint: .orange,
                    title: "Passphrase hors-canal",
                    body: "Les 6 mots de la passphrase ne sont jamais intégrés au QR ou au fichier. Tu les lis sur l'écran de l'envoyeur et tu les tapes à la main sur l'appareil receveur."
                )
                row(
                    systemImage: "eye.slash.fill",
                    tint: .indigo,
                    title: "Passphrase à usage unique",
                    body: "Chaque Handoff génère une passphrase fraîche. Si tu refais un Handoff plus tard, ce sera 6 nouveaux mots — la passphrase précédente ne ressert plus."
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("Comment ça marche")
        }
    }

    private func row(systemImage: String, tint: Color, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct HandoffNavigationRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var tint: Color = .accentColor
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
