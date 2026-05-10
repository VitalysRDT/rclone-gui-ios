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
//  Coverage :
//    - 69 backends categorised
//    - 69 backends with an explicit SF Symbol
//    - 69 backends with a French description
//    - 22 backends with a manual auth guide (link + numbered steps + paste)
//
//  Auth strategy: NO interactive OAuth in P1.
//    For each backend that needs auth, the wizard:
//    1. Opens the provider's developer console / API key page in Safari.
//    2. Walks the user through 3-5 short numbered steps.
//    3. Asks them to paste the resulting token / API key / JSON blob.
//    The pasted value lands in `parameters[tokenFieldName]` of
//    `config/create`. No browser callback, no Info.plist URL types,
//    no Universal Links infra needed.
//
//  Backends without an explicit override fall back to:
//    - category .specialized
//    - icon "externaldrive"
//    - description from rclone (English, OK for niche backends)
//

import Foundation

enum BackendOverrides {

    // MARK: - Category mapping (67 + 2 hidden)

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

    // MARK: - French descriptions (67 backends)

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

    // MARK: - Auth guides for the 22 backends that need a token / API key
    //
    // No OAuth is performed in-app. Each entry below tells the wizard:
    //   - which provider page to open (setupURL)
    //   - what the user has to do there (setupSteps)
    //   - which rclone field to fill (tokenFieldName)
    //   - how to label the input (tokenLabel) and hint format (tokenHint)
    //
    // The OAuth-specific fields (authURL/tokenURL/clientID/etc.) are kept
    // populated so a future P2 switch back to interactive OAuth is just a
    // strategy flip per backend.

    static let oauthConfigs: [String: OAuthProviderConfig] = [
        // ───────── Google family ─────────
        "drive": OAuthProviderConfig(
            backendName: "drive",
            authURL: URL(string: "https://accounts.google.com/o/oauth2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            defaultClientID: "202264815644.apps.googleusercontent.com",
            defaultClientSecret: "X4Z3ca8xfWDb1Voo-F9a7ZxMv3HCYUCY",
            defaultScopes: ["https://www.googleapis.com/auth/drive"],
            strategy: .manual,
            usePKCE: true,
            setupURL: URL(string: "https://developers.google.com/oauthplayground/?scopes=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive"),
            setupSteps: [
                "Ouvre Google OAuth Playground avec le bouton ci-dessous.",
                "Étape 1 : sélectionne « Drive API v3 → https://www.googleapis.com/auth/drive » puis clique « Authorize APIs ».",
                "Connecte-toi à ton compte Google et accepte les permissions.",
                "Étape 2 : clique « Exchange authorization code for tokens ».",
                "Copie le bloc JSON entier qui contient access_token + refresh_token, puis colle-le ci-dessous."
            ],
            tokenLabel: "Token JSON (Google OAuth Playground)",
            tokenFieldName: "token",
            tokenHint: "Format JSON : {\"access_token\":\"...\",\"refresh_token\":\"...\",\"expiry\":\"...\"}"
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
            usePKCE: true,
            setupURL: URL(string: "https://developers.google.com/oauthplayground/"),
            setupSteps: [
                "Ouvre Google OAuth Playground.",
                "Sélectionne les scopes Photos Library API : photoslibrary.readonly + photoslibrary.appendonly.",
                "Clique « Authorize APIs » et accepte avec ton compte Google.",
                "Clique « Exchange authorization code for tokens ».",
                "Copie le bloc JSON et colle-le ci-dessous."
            ],
            tokenLabel: "Token JSON (Google OAuth Playground)",
            tokenFieldName: "token",
            tokenHint: nil
        ),
        "google cloud storage": OAuthProviderConfig(
            backendName: "google cloud storage",
            authURL: URL(string: "https://accounts.google.com/o/oauth2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            defaultClientID: "202264815644.apps.googleusercontent.com",
            defaultClientSecret: "X4Z3ca8xfWDb1Voo-F9a7ZxMv3HCYUCY",
            defaultScopes: ["https://www.googleapis.com/auth/devstorage.full_control"],
            strategy: .manual,
            usePKCE: true,
            setupURL: URL(string: "https://console.cloud.google.com/iam-admin/serviceaccounts"),
            setupSteps: [
                "Ouvre Google Cloud Console → IAM → Service Accounts.",
                "Crée un service account avec le rôle « Storage Admin ».",
                "Onglet « Keys » → « Add Key » → « JSON » → télécharge le fichier.",
                "Ouvre le fichier JSON, copie tout son contenu, et colle-le ci-dessous."
            ],
            tokenLabel: "Service Account JSON",
            tokenFieldName: "service_account_credentials",
            tokenHint: "Le contenu complet du fichier JSON téléchargé depuis GCP."
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
            usePKCE: true,
            setupURL: URL(string: "https://rclone.org/onedrive/#getting-your-own-client-id-and-key"),
            setupSteps: [
                "Sur un poste avec rclone CLI : `rclone authorize \"onedrive\"`.",
                "Une page web s'ouvre — connecte-toi à ton compte Microsoft.",
                "Accepte les permissions demandées.",
                "Le terminal affiche un bloc JSON. Copie-le entièrement.",
                "Colle le JSON ci-dessous."
            ],
            tokenLabel: "Token JSON rclone (depuis `rclone authorize \"onedrive\"`)",
            tokenFieldName: "token",
            tokenHint: nil
        ),
        "azureblob": OAuthProviderConfig(
            backendName: "azureblob",
            authURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: ["https://storage.azure.com/.default"],
            strategy: .manual,
            usePKCE: true,
            setupURL: URL(string: "https://portal.azure.com/#@/blade/Microsoft_Azure_Storage/StorageAccountsBlade"),
            setupSteps: [
                "Ouvre Azure Portal → Storage accounts.",
                "Sélectionne ton compte → onglet « Access keys » → « Show keys ».",
                "Note le account name et la « key1 ».",
                "Dans le formulaire wizard, remplis « account » et « key » (pas besoin de token JSON ici)."
            ],
            tokenLabel: "Account Key (depuis Azure Portal)",
            tokenFieldName: "key",
            tokenHint: "Astuce : pour Azure, tu peux aussi remplir « account » + « key » directement dans le formulaire normal."
        ),
        "azurefiles": OAuthProviderConfig(
            backendName: "azurefiles",
            authURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: ["https://storage.azure.com/.default"],
            strategy: .manual,
            usePKCE: true,
            setupURL: URL(string: "https://portal.azure.com/"),
            setupSteps: [
                "Azure Portal → Storage accounts → ton compte.",
                "Onglet « Access keys » → copie account name + key1.",
                "Le wizard supporte aussi SAS et Service Principal — voir docs rclone."
            ],
            tokenLabel: "Account Key",
            tokenFieldName: "key",
            tokenHint: nil
        ),

        // ───────── Apple family ─────────
        "iclouddrive": OAuthProviderConfig(
            backendName: "iclouddrive",
            authURL: URL(string: "https://appleid.apple.com/")!,
            tokenURL: URL(string: "https://appleid.apple.com/")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://appleid.apple.com/account/manage"),
            setupSteps: [
                "Active la 2FA sur ton compte iCloud si pas déjà fait (obligatoire).",
                "Ouvre appleid.apple.com → section « Sign-In and Security ».",
                "« App-Specific Passwords » → « Generate Password » pour « Rclone GUI ».",
                "Copie le mot de passe au format abcd-efgh-ijkl-mnop.",
                "Colle-le ci-dessous (champ « password »).",
                "À l'étape précédente du wizard, remplis aussi « apple_id » avec ton email Apple ID."
            ],
            tokenLabel: "App-specific password Apple",
            tokenFieldName: "password",
            tokenHint: "Format : 4 groupes de 4 lettres séparés par des tirets. Le champ « apple_id » est rempli dans le formulaire principal."
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
            usePKCE: true,
            setupURL: URL(string: "https://www.dropbox.com/developers/apps"),
            setupSteps: [
                "Ouvre Dropbox App Console.",
                "« Create app » → choisis « Scoped access » + « Full Dropbox ».",
                "Donne un nom unique (ex : « rclonegui-vitalys »).",
                "Onglet « Permissions » → coche tous les scopes files.* et sharing.*. Sauvegarde.",
                "Onglet « Settings » → section « OAuth 2 » → « Generated access token » → « Generate ».",
                "Copie le token (commence par « sl. ») et colle-le ci-dessous.",
                "💡 Le wizard wrap automatiquement le raw token en JSON pour rclone."
            ],
            tokenLabel: "Generated access token Dropbox",
            tokenFieldName: "token",
            tokenHint: "Colle juste le raw token « sl.X… » — le wizard le formate en JSON automatiquement."
        ),
        "box": OAuthProviderConfig(
            backendName: "box",
            authURL: URL(string: "https://account.box.com/api/oauth2/authorize")!,
            tokenURL: URL(string: "https://api.box.com/oauth2/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: true,
            setupURL: URL(string: "https://app.box.com/developers/console"),
            setupSteps: [
                "Ouvre Box Developer Console.",
                "« Create New App » → « Custom App » → « User Authentication (OAuth 2.0) ».",
                "Onglet « Configuration » → section « Developer Token » → « Generate Developer Token ».",
                "Copie le token (valable 60 minutes seulement — re-génère si expiré).",
                "Colle-le ci-dessous."
            ],
            tokenLabel: "Developer Token Box",
            // rclone Box accepte un raw access_token via le champ dédié
            // `access_token` (pas le `token` JSON OAuth). Plus simple pour
            // le user que de générer un JSON token complet.
            tokenFieldName: "access_token",
            tokenHint: "⚠️ Token valide 60 minutes seulement. Pour un usage durable, créer une vraie app + JWT (voir docs rclone box)."
        ),
        "pcloud": OAuthProviderConfig(
            backendName: "pcloud",
            authURL: URL(string: "https://my.pcloud.com/oauth2/authorize")!,
            tokenURL: URL(string: "https://api.pcloud.com/oauth2_token")!,
            defaultClientID: "DnONSzyJXpm",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://my.pcloud.com/oauth2/authorize?client_id=DnONSzyJXpm&response_type=token&redirect_uri=https://my.pcloud.com"),
            setupSteps: [
                "Ouvre l'URL d'autorisation pCloud (lien ci-dessous).",
                "Connecte-toi à ton compte pCloud.",
                "Accepte l'accès rclone.",
                "L'URL de retour contient `access_token=...` dans la query string.",
                "Copie cette valeur (sans le préfixe access_token=) et colle-la ci-dessous."
            ],
            tokenLabel: "Access token pCloud",
            tokenFieldName: "access_token",
            tokenHint: "Long alphanumérique extrait de l'URL de retour."
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
            usePKCE: false,
            setupURL: URL(string: "https://oauth.yandex.com/authorize?response_type=token&client_id=ddffbc9bb6394f49a89e74a96a43b6f2"),
            setupSteps: [
                "Ouvre l'URL Yandex OAuth (lien ci-dessous).",
                "Connecte-toi à ton compte Yandex.",
                "Accepte l'accès rclone.",
                "Copie l'access_token affiché ou présent dans l'URL de redirection.",
                "Colle-le ci-dessous."
            ],
            tokenLabel: "Access token Yandex",
            tokenFieldName: "token",
            tokenHint: nil
        ),
        // mailru NOT in oauthConfigs : les champs `user` (email) et `pass`
        // sont déjà Required dans le schéma rclone et apparaissent dans le
        // formulaire normal. L'utilisateur les remplit là, pas besoin
        // d'écran d'authentification dédié.
        // → Mail.ru : 2FA + app password sur cloud.mail.ru → user/pass dans
        //   le formulaire de l'étape 2.

        // ───────── HiDrive / Huawei / Jottacloud / Premiumize / Putio / Sharefile / Zoho ─────────
        "hidrive": OAuthProviderConfig(
            backendName: "hidrive",
            authURL: URL(string: "https://my.hidrive.com/client/authorize")!,
            tokenURL: URL(string: "https://my.hidrive.com/oauth2/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: ["user,rw"],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://developer.hidrive.com/"),
            setupSteps: [
                "Pour HiDrive, le plus simple est `rclone authorize \"hidrive\"` sur un poste avec navigateur.",
                "Suis l'auth web Strato/HiDrive.",
                "Le terminal affiche un JSON token complet.",
                "Colle ce JSON ci-dessous."
            ],
            tokenLabel: "Token JSON rclone",
            tokenFieldName: "token",
            tokenHint: nil
        ),
        "huaweidrive": OAuthProviderConfig(
            backendName: "huaweidrive",
            authURL: URL(string: "https://oauth-login.cloud.huawei.com/oauth2/v3/authorize")!,
            tokenURL: URL(string: "https://oauth-login.cloud.huawei.com/oauth2/v3/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: ["openid", "https://www.huawei.com/auth/drive"],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://developer.huawei.com/consumer/en/console"),
            setupSteps: [
                "Le plus simple : `rclone authorize \"huaweidrive\"` sur un poste avec navigateur.",
                "Suis le flux Huawei ID.",
                "Copie le JSON token affiché dans le terminal.",
                "Colle-le ci-dessous."
            ],
            tokenLabel: "Token JSON rclone",
            tokenFieldName: "token",
            tokenHint: nil
        ),
        "jottacloud": OAuthProviderConfig(
            backendName: "jottacloud",
            authURL: URL(string: "https://jaccount.jottacloud.com/auth/realms/jottacloud/protocol/openid-connect/auth")!,
            tokenURL: URL(string: "https://jaccount.jottacloud.com/auth/realms/jottacloud/protocol/openid-connect/token")!,
            defaultClientID: "jottacli",
            defaultClientSecret: nil,
            defaultScopes: ["offline_access+openid"],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://www.jottacloud.com/web/secure"),
            setupSteps: [
                "Connecte-toi sur jottacloud.com.",
                "Profil → « Personal token » → génère un token CLI.",
                "Copie le token affiché.",
                "Colle-le ci-dessous (rclone le convertira en JSON token au premier usage)."
            ],
            tokenLabel: "Personal token Jottacloud",
            tokenFieldName: "token",
            tokenHint: nil
        ),
        "premiumizeme": OAuthProviderConfig(
            backendName: "premiumizeme",
            authURL: URL(string: "https://www.premiumize.me/authorize")!,
            tokenURL: URL(string: "https://www.premiumize.me/token")!,
            defaultClientID: "658877358",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://www.premiumize.me/account"),
            setupSteps: [
                "Connecte-toi sur premiumize.me.",
                "Mon Compte → onglet « Customer settings ».",
                "Copie l'« API Key ».",
                "Colle-la ci-dessous."
            ],
            tokenLabel: "API Key Premiumize",
            tokenFieldName: "api_key",
            tokenHint: nil
        ),
        "putio": OAuthProviderConfig(
            backendName: "putio",
            authURL: URL(string: "https://api.put.io/v2/oauth2/authenticate")!,
            tokenURL: URL(string: "https://api.put.io/v2/oauth2/access_token")!,
            defaultClientID: "4131",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://app.put.io/settings/account/oauth/apps"),
            setupSteps: [
                "Sur app.put.io → Settings → OAuth Apps.",
                "« Create new app » → donne un nom (ex : « Rclone GUI »).",
                "Le panel affiche un OAuth token immédiatement.",
                "Copie ce token et colle-le ci-dessous."
            ],
            tokenLabel: "OAuth token Put.io",
            tokenFieldName: "token",
            tokenHint: nil
        ),
        "sharefile": OAuthProviderConfig(
            backendName: "sharefile",
            authURL: URL(string: "https://secure.sharefile.com/oauth/authorize")!,
            tokenURL: URL(string: "https://secure.sharefile.com/oauth/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://api.sharefile.com/rest/getAuthorizationCode"),
            setupSteps: [
                "Le plus simple : `rclone authorize \"sharefile\"` sur un poste avec navigateur.",
                "rclone gère le subdomain probing automatiquement.",
                "Copie le JSON token retourné.",
                "Colle-le ci-dessous."
            ],
            tokenLabel: "Token JSON rclone",
            tokenFieldName: "token",
            tokenHint: nil
        ),
        "zoho": OAuthProviderConfig(
            backendName: "zoho",
            authURL: URL(string: "https://accounts.zoho.com/oauth/v2/auth")!,
            tokenURL: URL(string: "https://accounts.zoho.com/oauth/v2/token")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: ["WorkDrive.team.READ", "WorkDrive.workspace.READ", "WorkDrive.files.ALL"],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://api-console.zoho.com/"),
            setupSteps: [
                "Ouvre la Zoho API Console.",
                "Crée un client « Self Client ».",
                "Onglet « Generate Code » → scopes WorkDrive.* → durée 10 min.",
                "Échange le code contre un access_token via curl (voir docs rclone).",
                "Colle le JSON token ci-dessous."
            ],
            tokenLabel: "Token JSON Zoho",
            tokenFieldName: "token",
            tokenHint: nil
        ),

        // ───────── Token-only providers ─────────
        "filefabric": OAuthProviderConfig(
            backendName: "filefabric",
            authURL: URL(string: "https://www.smartfile.com/")!,
            tokenURL: URL(string: "https://www.smartfile.com/")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://www.smartfile.com/app/login/"),
            setupSteps: [
                "Connecte-toi à ton instance Enterprise File Fabric.",
                "Profil → « API Tokens » → « Generate new token ».",
                "Copie le permanent_token affiché.",
                "Colle-le ci-dessous."
            ],
            tokenLabel: "Permanent token File Fabric",
            tokenFieldName: "permanent_token",
            tokenHint: nil
        ),
        "linkbox": OAuthProviderConfig(
            backendName: "linkbox",
            authURL: URL(string: "https://linkbox.to/")!,
            tokenURL: URL(string: "https://linkbox.to/")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://www.linkbox.to/admin/account"),
            setupSteps: [
                "Connecte-toi sur linkbox.to → page Account.",
                "Section « API Token » → copie le token affiché (ou demande au support).",
                "Colle-le ci-dessous (champ « token »).",
                "À l'étape précédente du wizard, remplis aussi « email » et « password » (les identifiants Linkbox classiques) dans le formulaire principal."
            ],
            tokenLabel: "API Token Linkbox",
            tokenFieldName: "token",
            tokenHint: "⚠️ En plus du token, Linkbox demande email + password (remplis-les dans le formulaire principal)."
        ),
        "shade": OAuthProviderConfig(
            backendName: "shade",
            authURL: URL(string: "https://shade.inc/")!,
            tokenURL: URL(string: "https://shade.inc/")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://shade.inc/"),
            setupSteps: [
                "Connecte-toi à Shade et ouvre les paramètres compte.",
                "Génère un API token.",
                "Colle-le ci-dessous."
            ],
            tokenLabel: "API Token Shade",
            tokenFieldName: "token",
            tokenHint: nil
        ),
    ]

    // MARK: - Backends to hide on iOS

    static let hiddenOnIOS: Set<String> = [
        "tardigrade",   // Deprecated alias of storj
        "memory",       // In-process backend — no value to end-users
    ]
}
