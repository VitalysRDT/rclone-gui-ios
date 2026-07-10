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
//    Cette table est un SUR-ENSEMBLE statique indexé par nom de backend
//    rclone. Le wizard n'affiche QUE les backends réellement renvoyés par le
//    moteur embarqué via `config/providers` (cf. RemoteCatalogService) — les
//    entrées présentes ici pour des backends absents du rclone compilé sont
//    simplement inutilisées, jamais affichées. Les comptes ci-dessous sont
//    donc une « couverture catalogue », pas « ce qui est livré ».
//    - ~70 backends catégorisés / iconés / décrits en français.
//    - 24 backends avec un guide d'auth manuel (lien + étapes + collage),
//      dont Drime + Filen (nouveaux dans rclone 1.73).
//    - Internxt (1.73) utilise email + mot de passe dans le formulaire
//      dynamique (pas de token à coller) ; les comptes avec 2FA doivent
//      passer par le mode interactif (CLI).
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

/// Guide « où obtenir tes identifiants » affiché EN HAUT du formulaire
/// dynamique (DynamicRemoteFormView) pour les backends qui exigent une clé /
/// token / identifiants mais qui ne passent pas par l'étape OAuth (collage
/// d'un seul secret). Contrairement à `OAuthProviderConfig`, ce guide ne
/// collecte rien lui-même : il pointe l'utilisateur vers la bonne page et
/// nomme les champs à remplir. Convient aussi bien aux backends à un seul
/// secret (pixeldrain, 1Fichier, gofile) qu'à ceux à plusieurs champs
/// (imagekit, internetarchive, netstorage, storj).
struct BackendSetupGuide: Sendable, Hashable {
    /// Page provider à ouvrir pour générer la clé/token. `nil` = pas de page
    /// externe (ex : Sia auto-hébergé, Uloz.to en user/pass).
    let setupURL: URL?
    /// Étapes numérotées, courtes et actionnables (clé FR → String Catalog).
    let steps: [String]
    /// Avertissement optionnel d'une ligne.
    let note: String?
}

enum BackendOverrides {

    // MARK: - Category mapping (67 + 2 hidden)

    nonisolated static let categoryByBackend: [String: BackendCategory] = [
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

    nonisolated static let iconByBackend: [String: String] = [
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

    nonisolated static let frDescriptionByBackend: [String: String] = [
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

    nonisolated static let oauthConfigs: [String: OAuthProviderConfig] = [
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
                "Active la 2FA sur ton compte Apple si pas déjà fait (obligatoire).",
                "Utilise ton mot de passe Apple ID NORMAL — Apple refuse les mots de passe « spécifiques à une app » pour iCloud Drive.",
                "Sur ton iPhone : Réglages → [ton nom] → iCloud → active « Accéder aux données iCloud sur le web ».",
                "Colle ton mot de passe ci-dessous (champ « password »).",
                "Un code 2FA te sera demandé à l'étape « Récapitulatif » (test ou création).",
                "À l'étape précédente du wizard, remplis aussi « apple_id » avec ton email Apple ID."
            ],
            tokenLabel: "Mot de passe Apple ID",
            tokenFieldName: "password",
            tokenHint: "Ton mot de passe Apple ID complet — PAS un mot de passe d'app (rejeté par Apple). Le champ « apple_id » est rempli dans le formulaire principal."
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

        // ───────── Nouveaux backends rclone 1.73 ─────────
        // Drime : un seul champ utile, l'API Access Token créé sur le web.
        "drime": OAuthProviderConfig(
            backendName: "drime",
            authURL: URL(string: "https://app.drime.cloud/")!,
            tokenURL: URL(string: "https://app.drime.cloud/")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://app.drime.cloud/"),
            setupSteps: [
                "Connecte-toi à Drime sur le web (app.drime.cloud).",
                "Ouvre les Réglages du compte → onglet « Développeurs » (Developer).",
                "Crée un token (API Access Token) et nomme-le, ex : « Rclone GUI ».",
                "Copie le token affiché.",
                "Colle-le ci-dessous."
            ],
            tokenLabel: "API Access Token Drime",
            tokenFieldName: "access_token",
            tokenHint: "Token créé dans Réglages → Développeurs sur app.drime.cloud."
        ),
        // Filen : email + mot de passe se saisissent au formulaire (champs
        // Required du schéma rclone). Il manque la clé API, qui ne s'obtient
        // QUE via le CLI Filen (`filen export-api-key`) → on guide ici.
        "filen": OAuthProviderConfig(
            backendName: "filen",
            authURL: URL(string: "https://app.filen.io/")!,
            tokenURL: URL(string: "https://app.filen.io/")!,
            defaultClientID: "",
            defaultClientSecret: nil,
            defaultScopes: [],
            strategy: .manual,
            usePKCE: false,
            setupURL: URL(string: "https://github.com/FilenCloudDienste/filen-cli"),
            setupSteps: [
                "À l'étape précédente, remplis ton email et ton mot de passe Filen.",
                "Sur un ordinateur, installe le CLI Filen (lien ci-dessous).",
                "Connecte-toi avec `filen`, puis lance `filen export-api-key`.",
                "Copie la clé API affichée.",
                "Colle-la ci-dessous."
            ],
            tokenLabel: "Clé API Filen (commande `filen export-api-key`)",
            tokenFieldName: "api_key",
            tokenHint: "⚠️ La clé API s'obtient seulement via le CLI Filen sur ordinateur. Email + mot de passe se saisissent à l'étape Formulaire."
        ),
    ]

    // MARK: - Backends to hide on iOS

    nonisolated static let hiddenOnIOS: Set<String> = [
        "tardigrade",   // Deprecated alias of storj
        "memory",       // In-process backend — no value to end-users
    ]

    // MARK: - Setup guides (form path — clé / token sans OAuth)
    //
    // Backends qui ont des champs « clé/token/identifiants » dans le
    // formulaire mais sans tutoriel : on ajoute ici un encart « où obtenir
    // tes identifiants » (lien + étapes). Ne déclenche PAS l'étape OAuth.

    nonisolated static let setupGuides: [String: BackendSetupGuide] = [
        "pixeldrain": BackendSetupGuide(
            setupURL: URL(string: "https://pixeldrain.com/user/api_keys"),
            steps: [
                "Connecte-toi à ton compte Pixeldrain (abonnement requis pour l'accès complet).",
                "Ouvre la page « API keys » (lien ci-dessous) et génère une clé.",
                "Copie la clé et colle-la dans le champ « Api Key » du formulaire."
            ],
            note: "Lecture seule d'un dossier partagé possible sans clé : laisse « Api Key » vide et renseigne l'ID du dossier partagé."
        ),
        "fichier": BackendSetupGuide(
            setupURL: URL(string: "https://1fichier.com/console/params.pl"),
            steps: [
                "Connecte-toi sur 1fichier.com.",
                "Ouvre « Mon compte » → « Paramètres » (Console → Params, lien ci-dessous).",
                "Génère / copie ta clé API.",
                "Colle-la dans le champ « Api Key » du formulaire."
            ],
            note: "L'API 1Fichier requiert généralement un compte Premium."
        ),
        "imagekit": BackendSetupGuide(
            setupURL: URL(string: "https://imagekit.io/dashboard/developer/api-keys"),
            steps: [
                "Connecte-toi à ton dashboard ImageKit.io.",
                "Ouvre « Developer » → « API Keys » (lien ci-dessous).",
                "Copie ton URL endpoint, ta Public Key et ta Private Key.",
                "Renseigne « Endpoint », « Public Key » et « Private Key » dans le formulaire."
            ],
            note: nil
        ),
        "internetarchive": BackendSetupGuide(
            setupURL: URL(string: "https://archive.org/account/s3.php"),
            steps: [
                "Connecte-toi sur archive.org.",
                "Ouvre la page des clés S3 (lien ci-dessous).",
                "Copie ton « access key » et ta « secret key ».",
                "Renseigne « Access Key Id » et « Secret Access Key » dans le formulaire."
            ],
            note: "Laisse les deux champs vides pour un accès anonyme en lecture seule."
        ),
        "gofile": BackendSetupGuide(
            setupURL: URL(string: "https://gofile.io/myProfile"),
            steps: [
                "Connecte-toi sur gofile.io.",
                "Ouvre « My Profile » (lien ci-dessous).",
                "Copie ton « Account API token ».",
                "Colle-le dans le champ « Access Token » du formulaire."
            ],
            note: "Sans token, seul l'accès public/anonyme est possible."
        ),
        "sia": BackendSetupGuide(
            setupURL: nil,
            steps: [
                "Sia vise un nœud auto-hébergé (siad / renterd) que tu fais tourner toi-même.",
                "Renseigne « Api Url » avec l'adresse de ton démon (ex : http://mon-noeud:9980).",
                "Récupère le mot de passe dans le fichier « apipassword » du dossier .sia de ton nœud.",
                "Renseigne « Api Password » avec cette valeur."
            ],
            note: "Depuis iOS, le nœud Sia doit être accessible sur le réseau (pas en localhost)."
        ),
        "storj": BackendSetupGuide(
            setupURL: URL(string: "https://docs.storj.io/dcs/access"),
            steps: [
                "Ouvre la console Storj de ton projet (satellite, ex : us1.storj.io).",
                "Simple : crée un « Access Grant » et colle-le dans « Access Grant » (provider = existing).",
                "Avancé : provider = new, puis renseigne « Satellite Address », « Api Key » et « Passphrase ».",
                "Le lien ci-dessous explique comment générer ces accès."
            ],
            note: "La passphrase chiffre tes données : conserve-la, elle n'est pas récupérable."
        ),
        "netstorage": BackendSetupGuide(
            setupURL: URL(string: "https://control.akamai.com/"),
            steps: [
                "Dans Akamai Control Center, ouvre NetStorage → ton Storage Group.",
                "Récupère le « host » (domaine + chemin), le « account » (Upload Account) et la clé secrète G2O.",
                "Renseigne « Host », « Account » et « Secret » dans le formulaire."
            ],
            note: "Backend entreprise Akamai — nécessite un compte NetStorage."
        ),
        "ulozto": BackendSetupGuide(
            setupURL: nil,
            steps: [
                "Renseigne ton identifiant Uloz.to dans « Username » et ton mot de passe dans « Password ».",
                "Le champ « App Token » est optionnel — laisse-le vide."
            ],
            note: "L'app_token Uloz.to est réservé à leur app interne et peu fiable : préfère identifiant + mot de passe."
        ),
    ]
}
