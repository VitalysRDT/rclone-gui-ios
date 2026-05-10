//
//  BackendOverrides.swift
//  Rclone GUI — Core
//
//  Static lookups that augment the JSON catalog returned by
//  `config/providers`. Kept tiny on purpose: every entry that lives
//  here either does not exist in the rclone JSON (categorisation,
//  icons, FR translations, OAuth metadata) or actively contradicts
//  what we want users to see (hidden backends).
//
//  Coverage strategy:
//  - P0 (Sprint A/B/C): a minimal set so the wizard ships for the 10
//    smoke-test backends without blowing up on the rest.
//  - P1: every one of the 69 backends has a category+icon+FR description.
//  - P2: full FR catalog including obscure backends.
//
//  Backends without an explicit override fall back to:
//    - category .specialized
//    - icon "externaldrive"
//    - description from rclone (English, OK for niche backends)
//

import Foundation

enum BackendOverrides {

    // MARK: - Category mapping (P0 partial — covers smoke-test backends)

    static let categoryByBackend: [String: BackendCategory] = [
        // Cloud officiels
        "drive": .officialCloud,
        "dropbox": .officialCloud,
        "box": .officialCloud,
        "onedrive": .officialCloud,
        "google photos": .officialCloud,
        "google cloud storage": .officialCloud,
        "azureblob": .officialCloud,
        "azurefiles": .officialCloud,
        "iclouddrive": .officialCloud,
        "protondrive": .officialCloud,
        "mailru": .officialCloud,
        "yandex": .officialCloud,
        "huaweidrive": .officialCloud,
        "jottacloud": .officialCloud,
        "filescom": .officialCloud,

        // S3 compatible
        "s3": .s3Compatible,
        "b2": .s3Compatible,
        "swift": .s3Compatible,
        "oracleobjectstorage": .s3Compatible,
        "qingstor": .s3Compatible,
        "storj": .s3Compatible,

        // Sync grand public
        "mega": .mainstream,
        "pcloud": .mainstream,
        "sugarsync": .mainstream,
        "hidrive": .mainstream,
        "koofr": .mainstream,
        "seafile": .mainstream,
        "sharefile": .mainstream,
        "quatrix": .mainstream,
        "premiumizeme": .mainstream,
        "putio": .mainstream,
        "zoho": .mainstream,
        "filen": .mainstream,
        "drime": .mainstream,

        // Self-hosted / Standards
        "webdav": .selfHosted,
        "sftp": .selfHosted,
        "ftp": .selfHosted,
        "smb": .selfHosted,
        "http": .selfHosted,
        "hdfs": .selfHosted,

        // Wrappers / Composites
        "alias": .wrapper,
        "crypt": .wrapper,
        "cache": .wrapper,
        "chunker": .wrapper,
        "combine": .wrapper,
        "compress": .wrapper,
        "hasher": .wrapper,
        "union": .wrapper,
        "archive": .wrapper,

        // Local
        "local": .local,
    ]

    // MARK: - Icons (SF Symbols)

    static let iconByBackend: [String: String] = [
        "drive":         "g.circle.fill",
        "dropbox":       "shippingbox.fill",
        "box":           "cube.box.fill",
        "onedrive":      "square.stack.3d.up.fill",
        "google photos": "photo.on.rectangle.angled",
        "google cloud storage": "cylinder.split.1x2.fill",
        "azureblob":     "cube.transparent",
        "azurefiles":    "folder.fill",
        "iclouddrive":   "icloud.fill",
        "protondrive":   "lock.shield.fill",
        "yandex":        "y.circle.fill",
        "mailru":        "envelope.fill",
        "huaweidrive":   "h.circle.fill",
        "jottacloud":    "j.circle.fill",
        "filescom":      "f.circle.fill",
        "s3":            "cloud.fill",
        "b2":            "b.circle.fill",
        "swift":         "swift",
        "oracleobjectstorage": "o.circle.fill",
        "qingstor":      "q.circle.fill",
        "storj":         "shield.lefthalf.filled",
        "mega":          "m.circle.fill",
        "pcloud":        "p.circle.fill",
        "hidrive":       "h.square.fill",
        "koofr":         "k.circle.fill",
        "seafile":       "leaf.fill",
        "sharefile":     "square.and.arrow.up.fill",
        "premiumizeme":  "star.circle.fill",
        "putio":         "play.circle.fill",
        "zoho":          "z.circle.fill",
        "sftp":          "terminal.fill",
        "ftp":           "arrow.up.arrow.down.circle",
        "webdav":        "globe",
        "smb":           "network",
        "http":          "link.circle.fill",
        "hdfs":          "server.rack",
        "alias":         "link",
        "crypt":         "lock.shield.fill",
        "cache":         "hourglass",
        "chunker":       "rectangle.split.3x1.fill",
        "combine":       "rectangle.stack.fill",
        "compress":      "arrow.down.right.and.arrow.up.left",
        "hasher":        "checkmark.seal.fill",
        "union":         "rectangle.on.rectangle",
        "archive":       "archivebox.fill",
        "local":         "internaldrive.fill",
    ]

    // MARK: - French descriptions (P0 partial — high-priority backends only)

    static let frDescriptionByBackend: [String: String] = [
        "drive":         "Google Drive (compte personnel ou Workspace)",
        "dropbox":       "Dropbox",
        "box":           "Box",
        "onedrive":      "Microsoft OneDrive (perso ou Business)",
        "google photos": "Google Photos",
        "google cloud storage": "Google Cloud Storage (pas Drive)",
        "azureblob":     "Microsoft Azure Blob Storage",
        "azurefiles":    "Microsoft Azure Files",
        "iclouddrive":   "iCloud Drive et Photos",
        "protondrive":   "Proton Drive",
        "yandex":        "Yandex Disk",
        "mailru":        "Mail.ru Cloud",
        "s3":            "Amazon S3 et compatibles (Cloudflare R2, Wasabi, Backblaze, Minio…)",
        "b2":            "Backblaze B2",
        "swift":         "OpenStack Swift",
        "storj":         "Storj — stockage décentralisé",
        "mega":          "MEGA",
        "pcloud":        "pCloud",
        "hidrive":       "HiDrive",
        "koofr":         "Koofr (et compatibles : Digi Storage…)",
        "seafile":       "Seafile",
        "sftp":          "SSH/SFTP",
        "ftp":           "FTP",
        "webdav":        "WebDAV (Nextcloud, ownCloud, Synology…)",
        "smb":           "SMB / CIFS (Windows / Samba)",
        "http":          "HTTP en lecture seule",
        "alias":         "Alias d'un remote existant (raccourci)",
        "crypt":         "Chiffrement transparent au-dessus d'un autre remote",
        "cache":         "Cache local d'un remote distant",
        "chunker":       "Découpe les gros fichiers en morceaux",
        "combine":       "Combine plusieurs remotes en un seul",
        "compress":      "Compresse à la volée un autre remote",
        "hasher":        "Améliore les checksums d'un autre remote",
        "union":         "Fusionne le contenu de plusieurs remotes",
        "archive":       "Lit les archives (zip, tar…) d'un autre remote",
        "local":         "Disque local (sandbox de l'app)",
    ]

    // MARK: - OAuth configurations (P0 minimum: Drive only ; rest in P1)

    static let oauthConfigs: [String: OAuthProviderConfig] = [
        // P0: Drive (smoke-test target).
        // The default client_id/secret below are rclone's intentionally-public
        // shared credentials, identical to the ones embedded in rclone CLI's
        // open-source repository (cf. backend/drive/drive.go). They are NOT a
        // secret — Google considers them a "well-known" pair tied to the
        // shared rclone OAuth project. Power users should still override
        // both via the wizard's advanced section to escape the global rate
        // limit shared with every other rclone install.
        // See https://rclone.org/drive/#making-your-own-client-id
        "drive": OAuthProviderConfig(
            backendName: "drive",
            authURL: URL(string: "https://accounts.google.com/o/oauth2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            defaultClientID: "202264815644.apps.googleusercontent.com",
            defaultClientSecret: "X4Z3ca8xfWDb1Voo-F9a7ZxMv3HCYUCY",
            defaultScopes: ["https://www.googleapis.com/auth/drive"],
            // Drive forbids custom URL schemes. Real callback handling
            // lands in P0.11 (OAuthBrokerService) — stub here so the
            // catalog is complete.
            strategy: .manual,
            usePKCE: true
        ),
    ]

    // MARK: - Backends to hide on iOS

    static let hiddenOnIOS: Set<String> = [
        "tardigrade",   // Deprecated alias of storj
        "memory",       // In-process backend — no value to end-users
    ]
}
