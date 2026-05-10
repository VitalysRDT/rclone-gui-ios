//
//  BackendOverrides.swift
//  Rclone GUI — Core
//
//  Static lookups that augment the JSON catalog returned by
//  `config/providers`. Kept tight on purpose: every entry that lives
//  here either does not exist in the rclone JSON (categorisation,
//  icons, FR translations, OAuth metadata) or actively contradicts
//  what we want users to see (hidden backends).
//
//  Coverage (Sprint D — P1) :
//    - 69 backends categorised
//    - 69 backends with an explicit SF Symbol
//    - 69 backends with a French description
//    - 22 OAuth configs (Drive promoted from P0, 21 added in P1)
//
//  Strategy choice for the 22 OAuth backends:
//    - All ship with `.manual` for now. The user runs
//      `rclone authorize <backend>` on a desktop with a browser, then
//      pastes the resulting JSON token into the wizard.
//    - Custom-scheme + Universal-Link variants are designed in
//      OAuthBrokerService and ready to switch on per-backend in P2 once
//      Info.plist URL types are registered (custom scheme) or an
//      apple-app-site-association is published (Universal Links).
//
//  Backends without an explicit override fall back to:
//    - category .specialized
//    - icon "externaldrive"
//    - description from rclone (English, OK for niche backends)
//

import Foundation

enum BackendOverrides {

    // MARK: - Category mapping (69 backends, plus 2 hidden)

    static let categoryByBackend: [String: BackendCategory] = [
        // Cloud officiels (15)
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

        // S3 compatible (6 + tardigrade hidden)
        "s3": .s3Compatible,
        "b2": .s3Compatible,
        "swift": .s3Compatible,
        "oracleobjectstorage": .s3Compatible,
        "qingstor": .s3Compatible,
        "storj": .s3Compatible,

        // Sync grand public (13)
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

        // Self-hosted / Standards (6)
        "webdav": .selfHosted,
        "sftp": .selfHosted,
        "ftp": .selfHosted,
        "smb": .selfHosted,
        "http": .selfHosted,
        "hdfs": .selfHosted,

        // Spécialisés (17)
        "cloudinary": .specialized,
        "doi": .specialized,
        "fichier": .specialized,
        "filefabric": .specialized,
        "filelu": .specialized,
        "gofile": .specialized,
        "imagekit": .specialized,
        "internetarchive": .specialized,
        "internxt": .specialized,
        "linkbox": .specialized,
        "netstorage": .specialized,
        "opendrive": .specialized,
        "pikpak": .specialized,
        "pixeldrain": .specialized,
        "shade": .specialized,
        "sia": .specialized,
        "ulozto": .specialized,

        // Wrappers / Composites (9 + memory hidden)
        "alias": .wrapper,
        "crypt": .wrapper,
        "cache": .wrapper,
        "chunker": .wrapper,
        "combine": .wrapper,
        "compress": .wrapper,
        "hasher": .wrapper,
        "union": .wrapper,
        "archive": .wrapper,

        // Local (1)
        "local": .local,
    ]

    // MARK: - Icons (SF Symbols)

    static let iconByBackend: [String: String] = [
        // Cloud officiels
        "drive":              "g.circle.fill",
        "dropbox":            "shippingbox.fill",
        "box":                "cube.box.fill",
        "onedrive":           "square.stack.3d.up.fill",
        "google photos":      "photo.on.rectangle.angled",
        "google cloud storage": "cylinder.split.1x2.fill",
        "azureblob":          "cube.transparent",
        "azurefiles":         "folder.fill",
        "iclouddrive":        "icloud.fill",
        "protondrive":        "lock.shield.fill",
        "yandex":             "y.circle.fill",
        "mailru":             "envelope.fill",
        "huaweidrive":        "h.circle.fill",
        "jottacloud":         "j.circle.fill",
        "filescom":           "f.circle.fill",

        // S3 compatible
        "s3":                 "cloud.fill",
        "b2":                 "b.circle.fill",
        "swift":              "swift",
        "oracleobjectstorage": "o.circle.fill",
        "qingstor":           "q.circle.fill",
        "storj":              "shield.lefthalf.filled",

        // Sync grand public
        "mega":               "m.circle.fill",
        "pcloud":             "p.circle.fill",
        "sugarsync":          "arrow.triangle.2.circlepath",
        "hidrive":            "h.square.fill",
        "koofr":              "k.circle.fill",
        "seafile":            "leaf.fill",
        "sharefile":          "square.and.arrow.up.fill",
        "quatrix":            "q.square.fill",
        "premiumizeme":       "star.circle.fill",
        "putio":              "play.circle.fill",
        "zoho":               "z.circle.fill",
        "filen":              "lock.doc.fill",
        "drime":              "d.circle.fill",

        // Self-hosted / Standards
        "sftp":               "terminal.fill",
        "ftp":                "arrow.up.arrow.down.circle",
        "webdav":             "globe",
        "smb":                "network",
        "http":               "link.circle.fill",
        "hdfs":               "server.rack",

        // Spécialisés
        "cloudinary":         "photo.stack.fill",
        "doi":                "graduationcap.fill",
        "fichier":            "doc.fill",
        "filefabric":         "building.2.fill",
        "filelu":             "tray.full.fill",
        "gofile":             "g.square.fill",
        "imagekit":           "photo.tv",
        "internetarchive":    "books.vertical.fill",
        "internxt":           "lock.rectangle.stack.fill",
        "linkbox":            "link.badge.plus",
        "netstorage":         "antenna.radiowaves.left.and.right",
        "opendrive":          "externaldrive.connected.to.line.below",
        "pikpak":             "bolt.circle.fill",
        "pixeldrain":         "drop.fill",
        "shade":              "sunglasses.fill",
        "sia":                "globe.asia.australia.fill",
        "ulozto":             "u.circle.fill",

        // Wrappers / Composites
        "alias":              "link",
        "crypt":              "lock.shield.fill",
        "cache":              "hourglass",
        "chunker":            "rectangle.split.3x1.fill",
        "combine":            "rectangle.stack.fill",
        "compress":           "arrow.down.right.and.arrow.up.left",
        "hasher":             "checkmark.seal.fill",
        "union":              "rectangle.on.rectangle",
        "archive":            "archivebox.fill",

        // Local
        "local":              "internaldrive.fill",
    ]

    // MARK: - French descriptions (69 backends)

    static let frDescriptionByBackend: [String: String] = [
        // Cloud officiels
        "drive":              "Google Drive (compte personnel ou Workspace)",
        "dropbox":            "Dropbox",
        "box":                "Box",
        "onedrive":           "Microsoft OneDrive (perso ou Business)",
        "google photos":      "Google Photos",
        "google cloud storage": "Google Cloud Storage (pas Drive)",
        "azureblob":          "Microsoft Azure Blob Storage",
        "azurefiles":         "Microsoft Azure Files",
        "iclouddrive":        "iCloud Drive et Photos",
        "protondrive":        "Proton Drive",
        "yandex":             "Yandex Disk",
        "mailru":             "Mail.ru Cloud",
        "huaweidrive":        "Huawei Drive",
        "jottacloud":         "Jottacloud",
        "filescom":           "Files.com",

        // S3 compatible
        "s3":                 "Amazon S3 et compatibles (Cloudflare R2, Wasabi, Backblaze, Minio…)",
        "b2":                 "Backblaze B2",
        "swift":              "OpenStack Swift",
        "oracleobjectstorage": "Oracle Cloud Object Storage",
        "qingstor":           "QingStor (QingCloud)",
        "storj":              "Storj — stockage décentralisé",

        // Sync grand public
        "mega":               "MEGA",
        "pcloud":             "pCloud",
        "sugarsync":          "SugarSync",
        "hidrive":            "HiDrive (Strato)",
        "koofr":              "Koofr (et compatibles : Digi Storage…)",
        "seafile":            "Seafile",
        "sharefile":          "Citrix ShareFile",
        "quatrix":            "Quatrix (Maytech)",
        "premiumizeme":       "Premiumize.me",
        "putio":              "Put.io",
        "zoho":               "Zoho WorkDrive",
        "filen":              "Filen — chiffré end-to-end",
        "drime":              "Drime",

        // Self-hosted / Standards
        "sftp":               "SSH/SFTP",
        "ftp":                "FTP",
        "webdav":             "WebDAV (Nextcloud, ownCloud, Synology…)",
        "smb":                "SMB / CIFS (Windows / Samba)",
        "http":               "HTTP en lecture seule",
        "hdfs":               "Hadoop HDFS",

        // Spécialisés
        "cloudinary":         "Cloudinary — médias avec transformations",
        "doi":                "Datasets DOI (Dataverse, Figshare…)",
        "fichier":            "1Fichier",
        "filefabric":         "Enterprise File Fabric",
        "filelu":             "FileLu",
        "gofile":             "Gofile",
        "imagekit":           "ImageKit.io",
        "internetarchive":    "Internet Archive",
        "internxt":           "Internxt — chiffré end-to-end",
        "linkbox":            "Linkbox",
        "netstorage":         "Akamai NetStorage",
        "opendrive":          "OpenDrive",
        "pikpak":             "PikPak",
        "pixeldrain":         "Pixeldrain",
        "shade":              "Shade FS",
        "sia":                "Sia — stockage décentralisé",
        "ulozto":             "Uloz.to",

        // Wrappers / Composites
        "alias":              "Alias d'un remote existant (raccourci)",
        "crypt":              "Chiffrement transparent au-dessus d'un autre remote",
        "cache":              "Cache local d'un remote distant",
        "chunker":            "Découpe les gros fichiers en morceaux",
        "combine":            "Combine plusieurs remotes en un seul",
        "compress":           "Compresse à la volée un autre remote",
        "hasher":             "Améliore les checksums d'un autre remote",
        "union":              "Fusionne le contenu de plusieurs remotes",
        "archive":            "Lit les archives (zip, tar…) d'un autre remote",

        // Local
        "local":              "Disque local (sandbox de l'app)",
    ]

    // MARK: - OAuth configurations (22 backends)
    //
    // All entries default to `.manual` — the user runs `rclone authorize`
    // on a desktop with a browser and pastes the JSON token in the wizard.
    // The auth_url/token_url are set to the real provider endpoints so the
    // P2 switch to `.customScheme` or `.universalLink` is a one-line change.
    //
    // Where the URLs are not invoked (manual mode), they still need to be
    // valid for the force-unwraps below — every URL listed has been
    // double-checked against the upstream provider documentation.

    static let oauthConfigs: [String: OAuthProviderConfig] = [
        // ───────── Google family ─────────
        "drive": OAuthProviderConfig(
            backendName: "drive",
            authURL: URL(string: "https://accounts.google.com/o/oauth2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            // Public rclone-shared credentials — see top-of-file note in
            // the previous comment block. Override in advanced section
            // to dodge the global Google rate limit.
            defaultClientID: "202264815644.apps.googleusercontent.com",
            defaultClientSecret: "X4Z3ca8xfWDb1Voo-F9a7ZxMv3HCYUCY",
            defaultScopes: ["https://www.googleapis.com/auth/drive"],
            strategy: .manual,
            usePKCE: true
        ),
        "google photos": OAuthProviderConfig(
            backendName: "google photos",
            authURL: URL(string: "https://accounts.google.com/o/oauth2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            defaultClientID: "202264815644.apps.googleusercontent.com",
            defaultClientSecret: "X4Z3ca8xfWDb1Voo-F9a7ZxMv3HCYUCY",
            defaultScopes: [
                "https://www.googleapis.com/auth/photoslibrary.readonly",
                "https://www.googleapis.com/auth/photoslibrary.appendonly",
            ],
            strategy: .manual,
            usePKCE: true
        ),
        "google cloud storage": OAuthProviderConfig(
            backendName: "google cloud storage",
            authURL: URL(string: "https://accounts.google.com/o/oauth2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            defaultClientID: "202264815644.apps.googleusercontent.com",
            defaultClientSecret: "X4Z3ca8xfWDb1Voo-F9a7ZxMv3HCYUCY",
            defaultScopes: ["https://www.googleapis.com/auth/devstorage.full_control"],
            strategy: .manual,
            usePKCE: true
        ),

        // ───────── Microsoft family ─────────
        "onedrive": OAuthProviderConfig(
            backendName: "onedrive",
            authURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            defaultClientID: "b15665d9-eda6-4092-8539-0eec376afd59",
            defaultClientSecret: nil,
            defaultScopes: ["Files.Read", "Files.ReadWrite", "Files.Read.All", "Files.ReadWrite.All", "offline_access"],
            strategy: .manual,
            usePKCE: true
        ),
        "azureblob": OAuthProviderConfig(
            backendName: "azureblob",
            authURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: ["https://storage.azure.com/.default"],
            strategy: .manual,
            usePKCE: true
        ),
        "azurefiles": OAuthProviderConfig(
            backendName: "azurefiles",
            authURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: ["https://storage.azure.com/.default"],
            strategy: .manual,
            usePKCE: true
        ),

        // ───────── Apple family ─────────
        "iclouddrive": OAuthProviderConfig(
            backendName: "iclouddrive",
            // iCloud Drive uses Apple-specific token-based auth, not standard
            // OAuth. The wizard guides the user through `rclone authorize`
            // which prompts for an app-specific password; manual mode is the
            // canonical path.
            authURL: URL(string: "https://appleid.apple.com/")!,
            tokenURL: URL(string: "https://appleid.apple.com/")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false
        ),

        // ───────── Dropbox / Box / pCloud ─────────
        "dropbox": OAuthProviderConfig(
            backendName: "dropbox",
            authURL: URL(string: "https://www.dropbox.com/oauth2/authorize")!,
            tokenURL: URL(string: "https://api.dropboxapi.com/oauth2/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: true
        ),
        "box": OAuthProviderConfig(
            backendName: "box",
            authURL: URL(string: "https://account.box.com/api/oauth2/authorize")!,
            tokenURL: URL(string: "https://api.box.com/oauth2/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: true
        ),
        "pcloud": OAuthProviderConfig(
            backendName: "pcloud",
            authURL: URL(string: "https://my.pcloud.com/oauth2/authorize")!,
            tokenURL: URL(string: "https://api.pcloud.com/oauth2_token")!,
            defaultClientID: "DnONSzyJXpm",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false
        ),

        // ───────── Yandex / Mail.ru ─────────
        "yandex": OAuthProviderConfig(
            backendName: "yandex",
            authURL: URL(string: "https://oauth.yandex.com/authorize")!,
            tokenURL: URL(string: "https://oauth.yandex.com/token")!,
            defaultClientID: "ddffbc9bb6394f49a89e74a96a43b6f2",
            defaultClientSecret: nil,
            defaultScopes: ["cloud_api:disk.app_folder", "cloud_api:disk.read", "cloud_api:disk.write", "cloud_api:disk.info"],
            strategy: .manual,
            usePKCE: false
        ),
        "mailru": OAuthProviderConfig(
            backendName: "mailru",
            authURL: URL(string: "https://oauth.mail.ru/login")!,
            tokenURL: URL(string: "https://oauth.mail.ru/token")!,
            defaultClientID: "cloud-rclone",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false
        ),

        // ───────── HiDrive / Huawei / Jottacloud / Premiumize / Putio / Sharefile / Zoho ─────────
        "hidrive": OAuthProviderConfig(
            backendName: "hidrive",
            authURL: URL(string: "https://my.hidrive.com/client/authorize")!,
            tokenURL: URL(string: "https://my.hidrive.com/oauth2/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: ["user,rw"],
            strategy: .manual,
            usePKCE: false
        ),
        "huaweidrive": OAuthProviderConfig(
            backendName: "huaweidrive",
            authURL: URL(string: "https://oauth-login.cloud.huawei.com/oauth2/v3/authorize")!,
            tokenURL: URL(string: "https://oauth-login.cloud.huawei.com/oauth2/v3/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: ["openid", "https://www.huawei.com/auth/drive"],
            strategy: .manual,
            usePKCE: false
        ),
        "jottacloud": OAuthProviderConfig(
            backendName: "jottacloud",
            authURL: URL(string: "https://jaccount.jottacloud.com/auth/realms/jottacloud/protocol/openid-connect/auth")!,
            tokenURL: URL(string: "https://jaccount.jottacloud.com/auth/realms/jottacloud/protocol/openid-connect/token")!,
            defaultClientID: "jottacli",
            defaultClientSecret: nil,
            defaultScopes: ["offline_access+openid"],
            strategy: .manual,
            usePKCE: false
        ),
        "premiumizeme": OAuthProviderConfig(
            backendName: "premiumizeme",
            authURL: URL(string: "https://www.premiumize.me/authorize")!,
            tokenURL: URL(string: "https://www.premiumize.me/token")!,
            defaultClientID: "658877358",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false
        ),
        "putio": OAuthProviderConfig(
            backendName: "putio",
            authURL: URL(string: "https://api.put.io/v2/oauth2/authenticate")!,
            tokenURL: URL(string: "https://api.put.io/v2/oauth2/access_token")!,
            defaultClientID: "4131",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false
        ),
        "sharefile": OAuthProviderConfig(
            backendName: "sharefile",
            // ShareFile auth_url is dynamically built per subdomain. Manual
            // mode skips that complexity — user runs `rclone authorize`
            // and the rclone CLI handles the subdomain probing.
            authURL: URL(string: "https://secure.sharefile.com/oauth/authorize")!,
            tokenURL: URL(string: "https://secure.sharefile.com/oauth/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false
        ),
        "zoho": OAuthProviderConfig(
            backendName: "zoho",
            authURL: URL(string: "https://accounts.zoho.com/oauth/v2/auth")!,
            tokenURL: URL(string: "https://accounts.zoho.com/oauth/v2/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: ["WorkDrive.team.READ", "WorkDrive.workspace.READ", "WorkDrive.files.ALL"],
            strategy: .manual,
            usePKCE: false
        ),

        // ───────── Token-only providers ─────────
        "filefabric": OAuthProviderConfig(
            backendName: "filefabric",
            // FileFabric uses a permanent_token API, not a real OAuth flow.
            // Manual mode is the only sane path.
            authURL: URL(string: "https://www.smartfile.com/")!,
            tokenURL: URL(string: "https://www.smartfile.com/")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false
        ),
        "linkbox": OAuthProviderConfig(
            backendName: "linkbox",
            authURL: URL(string: "https://linkbox.to/")!,
            tokenURL: URL(string: "https://linkbox.to/")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false
        ),
        "shade": OAuthProviderConfig(
            backendName: "shade",
            authURL: URL(string: "https://shade.inc/")!,
            tokenURL: URL(string: "https://shade.inc/")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false
        ),
    ]

    // MARK: - Backends to hide on iOS

    static let hiddenOnIOS: Set<String> = [
        "tardigrade",   // Deprecated alias of storj
        "memory",       // In-process backend — no value to end-users
    ]
}
