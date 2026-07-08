//
//  ChangelogView.swift
//  Rclone GUI — Views/Settings
//
//  Historique des versions (« Nouveautés ») accessible depuis Réglages.
//  Contenu bilingue FR/EN rendu en `verbatim` : il est localisé à la main
//  (FR pour les appareils français, EN sinon) et n'alimente donc PAS le
//  String Catalog — on évite tout reformatage du catalogue. Le contenu
//  reflète l'historique publié sur rclone.rougetet.com.
//

import SwiftUI

struct ChangelogView: View {
    private var useFrench: Bool {
        Locale.current.language.languageCode?.identifier == "fr"
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        Form {
            ForEach(Self.releases, id: \.version) { release in
                Section {
                    ForEach(Array((useFrench ? release.itemsFR : release.itemsEN).enumerated()), id: \.offset) { _, item in
                        Label {
                            Text(verbatim: item)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    header(for: release)
                }
            }
        }
        .navigationTitle(useFrench ? "Historique des versions" : "Version history")
        #if os(iOS)
        .rgInlineNavTitle()
        #endif
    }

    @ViewBuilder
    private func header(for release: Release) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: (useFrench ? "Version " : "Version ") + release.version)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if release.version == currentVersion {
                Text(verbatim: useFrench ? "ACTUELLE" : "CURRENT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
            Spacer()
            Text(verbatim: useFrench ? release.dateFR : release.dateEN)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
    }

    private struct Release {
        let version: String
        let dateFR: String
        let dateEN: String
        let itemsFR: [String]
        let itemsEN: [String]
    }

    // Historique aligné sur rclone.rougetet.com (le plus récent en premier).
    private static let releases: [Release] = [
        Release(
            version: "1.9.2", dateFR: "Juillet 2026", dateEN: "July 2026",
            itemsFR: [
                "Avancement des téléchargements de dossier : la barre de progression s'affiche enfin (la taille du dossier est pré-calculée avant le transfert).",
            ],
            itemsEN: [
                "Folder download progress: the progress bar is finally shown (the folder size is precomputed before the transfer starts).",
            ]
        ),
        Release(
            version: "1.9", dateFR: "Juin 2026", dateEN: "June 2026",
            itemsFR: [
                "Lecteur vidéo refondu : ouverture plus rapide et lecture bien plus robuste des fichiers 4K MKV/HEVC (nouveau moteur VLCKit 4), audio sans grésillement et meilleure sélection des pistes audio et des sous-titres.",
                "Picture-in-Picture vidéo : l'image continue dans une fenêtre flottante quand vous quittez l'app — avant, seul le son se poursuivait.",
                "« Ouvrir dans une autre app » fiabilisé (Infuse, VLC, nPlayer…) : le fichier est d'abord téléchargé puis transmis via le partage iOS, fini l'erreur d'ouverture du flux.",
                "Audio en arrière-plan : la musique, les podcasts et les livres audio continuent quand l'app passe en fond ou que l'écran se verrouille, avec les contrôles sur l'écran verrouillé.",
                "Mini-lecteur audio persistant : une barre « en cours de lecture » avec pochette reste visible pendant que vous naviguez ; touchez-la pour le lecteur plein écran (grande pochette, barre de progression, file de lecture).",
                "Visionneuse photo : ouvrez une image en plein écran et faites défiler vos photos d'un glissement, avec zoom (pincer / double-tap) et partage.",
                "Flows & automatisations : lancez la synchro photo, sauvegardez un dossier ou mettez les transferts en pause/reprise depuis Raccourcis et Siri — 100 % en local.",
                "Nouveaux réglages de lecture : audio en arrière-plan, PiP automatique et vitesse de lecture par défaut.",
                "Performances : application nettement plus fluide — moins de gels, navigation, vignettes et transferts optimisés.",
            ],
            itemsEN: [
                "Rebuilt video player: faster startup and far more robust playback of 4K MKV/HEVC files (new VLCKit 4 engine), crackle-free audio, and better audio-track and subtitle selection.",
                "Picture-in-Picture for video: the picture keeps playing in a floating window when you leave the app — previously only the sound continued.",
                "More reliable \"Open in another app\" (Infuse, VLC, nPlayer…): the file is downloaded first, then handed off via the iOS share sheet — no more stream-opening errors.",
                "Background audio: music, podcasts and audiobooks keep playing when the app goes to the background or the screen locks, with lock-screen controls.",
                "Persistent audio mini-player: a \"now playing\" bar with artwork stays visible while you browse; tap it for the full-screen player (large artwork, scrubber, play queue).",
                "Photo viewer: open an image full-screen and swipe through your photos, with pinch / double-tap zoom and sharing.",
                "Flows & automations: run photo sync, back up a folder, or pause/resume transfers from Shortcuts and Siri — fully on-device.",
                "New playback settings: background audio, automatic PiP and default playback speed.",
                "Performance: a noticeably smoother app — fewer freezes, with optimized browsing, thumbnails and transfers.",
            ]
        ),
        Release(
            version: "1.8", dateFR: "Juin 2026", dateEN: "June 2026",
            itemsFR: [
                "Transferts Pro : file d'attente avec nombre de transferts simultanés réglable, et réordonnancement par glisser-déposer.",
                "Pause et reprise transfert par transfert (plus seulement tout d'un coup), avec priorités et indicateur de file.",
                "Reprise automatique après une coupure réseau ou un redémarrage de l'app.",
                "Réglages réseau : limite de débit distincte en Wi-Fi et en cellulaire, et option « pause en cellulaire ».",
                "Logs de transfert exportables pour diagnostiquer un envoi ou un téléchargement.",
                "Création de dossier directement depuis le navigateur de fichiers.",
                "Nouvel écran « Historique des versions » dans les Réglages.",
                "Vue galerie : vignettes mieux alignées (fini les chevauchements sur petit écran).",
                "Corrections de stabilité et de fiabilité des transferts.",
            ],
            itemsEN: [
                "Pro Transfers: a queue with an adjustable number of simultaneous transfers, plus drag-and-drop reordering.",
                "Pause and resume each transfer individually (not just all at once), with priorities and a queue indicator.",
                "Automatic resume after a network drop or an app restart.",
                "Network settings: separate speed limits for Wi-Fi and cellular, plus a \"pause on cellular\" option.",
                "Exportable transfer logs to diagnose an upload or a download.",
                "Create a folder right from the file browser.",
                "New \"Version history\" screen in Settings.",
                "Gallery view: better-aligned thumbnails (no more overlapping on small screens).",
                "Stability and transfer reliability fixes.",
            ]
        ),
        Release(
            version: "1.7", dateFR: "Juin 2026", dateEN: "June 2026",
            itemsFR: [
                "Téléchargez des dossiers entiers en une fois (récursif).",
                "Raccourcis & Siri : ouvrez un remote ou lancez un envoi de fichier depuis l'app Raccourcis, grâce aux App Intents.",
                "Confidentialité renforcée : le cache média est effacé automatiquement au verrouillage par inactivité, et vous pouvez plafonner sa taille (éviction automatique).",
                "Transferts plus fiables : les transferts échoués sont relancés automatiquement, dans une limite raisonnable.",
                "Assistant guidé pour créer votre coffre chiffré « Crypt ».",
                "Journaux internes en direct pour diagnostiquer une connexion.",
                "Nouvel écran « Feuille de route » pour découvrir ce qui arrive.",
                "Améliorations de stabilité et de performance.",
            ],
            itemsEN: [
                "Download entire folders in one go (recursive).",
                "Shortcuts & Siri: open a remote or start a file upload from the Shortcuts app, powered by App Intents.",
                "Stronger privacy: the media cache is wiped automatically when the app locks on inactivity, and you can cap its size (automatic eviction).",
                "More reliable transfers: failed transfers are retried automatically, within a sensible limit.",
                "Guided assistant to set up your encrypted \"Crypt\" vault.",
                "Live internal logs to diagnose a connection.",
                "New \"Roadmap\" screen to see what's coming next.",
                "Stability and performance improvements.",
            ]
        ),
        Release(
            version: "1.6", dateFR: "Juin 2026", dateEN: "June 2026",
            itemsFR: [
                "Connexion par fichier : quand un backend exige un fichier pour s'authentifier (clé privée SSH, known_hosts, JSON de compte de service Google, certificat TLS…), importez-le directement depuis Fichiers — fini les chemins impossibles à saisir.",
                "Les identifiants importés sont copiés en sécurité sur l'appareil et ne sont jamais transmis ailleurs.",
                "Améliorations de stabilité et de performance.",
            ],
            itemsEN: [
                "Connect with a file: when a backend needs a file to sign in (SSH private key, known_hosts, Google service-account JSON, TLS certificate…), import it straight from Files — no more impossible-to-type paths.",
                "Imported credentials are copied securely on-device and never sent anywhere else.",
                "Stability and performance improvements.",
            ]
        ),
        Release(
            version: "1.5", dateFR: "Juin 2026", dateEN: "June 2026",
            itemsFR: [
                "Lecteur vidéo intégré multi-format (MKV, AVI, WebM, TS…) : sous-titres intégrés et fichiers externes, pistes audio, reprise là où vous étiez.",
                "Au choix : lecture dans l'app ou dans une app externe (Infuse, VLC).",
                "Galerie en grille avec vignettes pour photos et vidéos : bascule liste/grille, mode « Médias uniquement », génération des vignettes en Wi-Fi par défaut.",
                "Nouvelle option pour exclure les données de l'app des sauvegardes iCloud.",
                "Stabilité et performances.",
            ],
            itemsEN: [
                "Built-in multi-format video player (MKV, AVI, WebM, TS…): embedded and sidecar subtitles, audio tracks, resume where you left off.",
                "Your choice: play in-app or in an external app (Infuse, VLC).",
                "Grid gallery with thumbnails for photos and videos: list/grid toggle, \"Media only\" mode, Wi-Fi-only thumbnail generation by default.",
                "New option to exclude the app's data from iCloud backups.",
                "Stability and performance improvements.",
            ]
        ),
        Release(
            version: "1.4", dateFR: "Juin 2026", dateEN: "June 2026",
            itemsFR: [
                "Nouveaux clouds : Drime, Internxt et Filen (Internxt et Filen chiffrés de bout en bout).",
                "Panneau « où trouver vos identifiants » pour Pixeldrain, 1Fichier, ImageKit, Internet Archive, Gofile, Storj, NetStorage…",
                "Sélecteur de stockage pour les remotes composites (alias, union, combine) — fini la saisie manuelle de « remote:chemin ».",
                "Correction de la connexion aux remotes protégés par mot de passe (SFTP, FTP, WebDAV, SMB…).",
                "Remotes verrouillés masqués des Récents et Favoris.",
            ],
            itemsEN: [
                "New clouds: Drime, Internxt and Filen (Internxt and Filen are end-to-end encrypted).",
                "\"Where to get your credentials\" panel for Pixeldrain, 1Fichier, ImageKit, Internet Archive, Gofile, Storj, NetStorage…",
                "Storage picker for composite remotes (alias, union, combine) — no more typing \"remote:path\" by hand.",
                "Fixed connecting to password-protected remotes (SFTP, FTP, WebDAV, SMB…).",
                "Locked remotes hidden from Recents and Favorites.",
            ]
        ),
        Release(
            version: "1.3", dateFR: "Juin 2026", dateEN: "June 2026",
            itemsFR: [
                "Correctif important : l'import d'une configuration rclone chiffrée par mot de passe ne plante plus.",
                "Bouton « J'ai un code » pour utiliser des codes promo.",
                "Page « Contacter le développeur » dans Réglages → Support.",
                "Traduction anglaise complète de l'app + code source désormais public sur GitHub.",
            ],
            itemsEN: [
                "Important fix: importing a password-encrypted rclone configuration no longer crashes the app.",
                "\"I have a code\" button to redeem promo codes.",
                "\"Contact the Developer\" page in Settings → Support.",
                "Completed English translation across the whole app + source code now public on GitHub.",
            ]
        ),
        Release(
            version: "1.2", dateFR: "Juin 2026", dateEN: "June 2026",
            itemsFR: [
                "App macOS native (Mac Apple Silicon) : barre latérale et intégration Finder.",
                "Assistant guidé pour les remotes chiffrés (crypt) : choix du stockage, navigation jusqu'au dossier, mot de passe — sans saisie de chemin.",
                "Assistant d'ajout amélioré : bouton Retour et sélecteur de fichier natif pour importer rclone.conf.",
            ],
            itemsEN: [
                "Native macOS app (Apple Silicon Macs): sidebar layout and Finder integration.",
                "Guided wizard for encrypted (crypt) remotes: pick storage, browse to the folder, set a password — no manual path typing.",
                "Improved add-remote wizard: Back button and native file picker to import rclone.conf.",
            ]
        ),
        Release(
            version: "1.1", dateFR: "Mai 2026", dateEN: "May 2026",
            itemsFR: [
                "Localisation anglaise complète : l'interface suit la langue de l'appareil.",
                "Première ouverture plus fluide, stabilité et finitions.",
            ],
            itemsEN: [
                "Full English localization: the interface follows your device language.",
                "Smoother first-launch, stability and polish.",
            ]
        ),
        Release(
            version: "1.0", dateFR: "Mai 2026", dateEN: "May 2026",
            itemsFR: [
                "Première version publique : client rclone natif, 70+ backends, intégration Fichiers (File Provider), chiffrement crypt de bout en bout, sync photo, Face ID, zéro tracking.",
            ],
            itemsEN: [
                "First public release: native rclone client, 70+ backends, Files integration (File Provider), end-to-end crypt encryption, photo sync, Face ID, zero tracking.",
            ]
        ),
    ]
}
