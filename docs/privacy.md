---
layout: default
title: Rclone GUI — Privacy Policy
---

# Rclone GUI — Privacy Policy

**Dernière mise à jour : 16 mai 2026**
*Last updated: May 16, 2026*

---

## Français

Rclone GUI (« l'application ») est un client iOS pour rclone permettant de connecter, naviguer et synchroniser vos fichiers entre votre appareil et vos services de stockage cloud personnels (Amazon S3, Backblaze B2, Cloudflare R2, Dropbox, Google Drive, Microsoft OneDrive, Storj, Wasabi, et plus de 60 autres backends compatibles rclone).

### 1. Données que nous ne collectons pas

L'application **ne collecte, ne transmet et ne stocke aucune donnée personnelle sur un serveur que nous contrôlons**. Nous ne possédons aucun serveur dorsal.

Concrètement :

- Aucune analytics, aucun SDK de tracking, aucun outil tiers de mesure d'audience.
- Aucune télémétrie d'usage.
- Aucun rapport de crash transmis à un tiers autre qu'Apple (TestFlight / App Store Connect, conformément à vos réglages iOS « Partager l'analyse iPhone »).
- Aucun identifiant publicitaire (IDFA) n'est lu.
- Aucun compte ni inscription n'est requis pour utiliser l'application.

### 2. Données stockées localement sur votre appareil

Pour fonctionner, l'application stocke les éléments suivants **uniquement sur votre appareil**, jamais sur un serveur distant que nous contrôlons :

| Donnée | Emplacement | Chiffrement |
|---|---|---|
| Configuration rclone (URLs des remotes, identifiants) | Conteneur sandbox de l'app + App Group | Chiffrée au repos avec ChaCha20-Poly1305 ; clé maître dans le Trousseau iOS |
| Jetons OAuth des fournisseurs cloud que vous configurez | Trousseau iOS partagé du groupe d'app | Chiffrement matériel du Trousseau iOS |
| Préférences d'interface | UserDefaults | Aucun (préférences non sensibles) |
| Fichiers téléchargés ou pré-cachés | Dossier Caches / FileProvider du sandbox | Protection iOS `.completeFileProtection` |
| Diagnostics IPC FileProvider (logs techniques) | Conteneur App Group | Identifiants remote/chemin **hachés SHA-256** avant écriture |

Vous pouvez à tout moment effacer ces données en désinstallant l'application.

### 3. Communications réseau

L'application communique directement avec :

1. **Les services cloud que vous configurez vous-même** (S3, Google Drive, etc.) via leur API officielle, en HTTPS. Vos identifiants et tokens transitent uniquement entre votre appareil et ces services. Apple App Transport Security (ATS) est activé sans exception.
2. **Un serveur HTTP localhost (`127.0.0.1`)** lancé par l'application pour permettre à AVPlayer de lire vos vidéos déchiffrées à la volée. Ce trafic ne quitte jamais l'appareil.
3. **Aucun autre serveur.** Pas de domaine sous notre contrôle, pas de webhook, pas de service tiers de notification.

### 4. Authentification biométrique (Face ID / Touch ID)

Si vous activez la protection biométrique, l'application utilise `LocalAuthentication` pour vérifier votre identité au lancement. **La biométrie ne quitte jamais le Secure Enclave de votre iPhone** et n'est jamais transmise à l'application ni à nous. Apple n'expose qu'un résultat booléen.

### 5. Photos et bibliothèque média

Si vous activez la synchronisation photo, l'application accède à votre photothèque uniquement pour uploader les éléments que vous lui désignez, vers le service cloud que vous avez configuré. Aucune photo n'est envoyée à un autre destinataire.

### 6. Extension Fichiers (File Provider)

L'extension intégrée à l'app Fichiers d'Apple opère dans un sandbox iOS distinct. Elle ne dispose que des permissions nécessaires pour énumérer et matérialiser les fichiers que vous demandez à ouvrir.

### 7. Vos droits (RGPD)

Étant donné qu'aucune donnée personnelle ne nous est transmise, il n'existe rien à supprimer, exporter ou rectifier de notre côté. Pour révoquer un accès cloud, retirez l'autorisation dans le tableau de bord du service concerné (par exemple : `myaccount.google.com/permissions`).

### 8. Logiciel libre

L'application embarque [rclone](https://rclone.org) (MIT) et plusieurs bibliothèques open source. Le code source de Rclone GUI est disponible sur GitHub : <https://github.com/VitalysRDT/rclone-gui-ios>.

### 9. Contact

Pour toute question relative à cette politique de confidentialité :

**Vitalys Rougetet — De Troyane**
Email : <vitalys@rougetet.com>

---

## English

Rclone GUI (the "App") is an iOS client for rclone that lets you connect, browse, and sync files between your device and your own cloud storage services (Amazon S3, Backblaze B2, Cloudflare R2, Dropbox, Google Drive, Microsoft OneDrive, Storj, Wasabi, and 60+ other rclone-compatible backends).

### 1. Data we do not collect

The App **does not collect, transmit, or store any personal data on any server we control**. We operate no backend infrastructure.

Specifically:

- No analytics, no tracking SDK, no third-party audience measurement.
- No usage telemetry.
- No crash reporting to any party other than Apple (TestFlight / App Store Connect, subject to your "Share iPhone Analytics" iOS setting).
- No reading of the advertising identifier (IDFA).
- No account or sign-up required.

### 2. Data stored locally on your device

To function, the App stores the following items **only on your device**, never on a remote server we control:

| Data | Location | Encryption |
|---|---|---|
| Rclone configuration (remote URLs, credentials) | App sandbox + App Group container | At-rest ChaCha20-Poly1305; master key in iOS Keychain |
| OAuth tokens for the cloud providers you configure | Shared iOS Keychain (app group) | iOS Keychain hardware encryption |
| UI preferences | UserDefaults | None (non-sensitive) |
| Downloaded / pre-cached files | Caches / FileProvider sandbox folder | iOS `.completeFileProtection` |
| FileProvider IPC diagnostics (technical logs) | App Group container | Remote names and paths **SHA-256 hashed** before writing |

You can erase all of this at any time by uninstalling the App.

### 3. Network communications

The App talks directly to:

1. **The cloud services you configure yourself** (S3, Google Drive, etc.) via their official APIs over HTTPS. Your credentials and tokens travel only between your device and those services. Apple App Transport Security (ATS) is enabled with no exception.
2. **A localhost HTTP server (`127.0.0.1`)** spawned by the App to let AVPlayer stream your decrypted media on the fly. This traffic never leaves the device.
3. **No other servers.** No domain under our control, no webhook, no third-party notification service.

### 4. Biometric authentication (Face ID / Touch ID)

If you enable biometric protection, the App uses `LocalAuthentication` to verify you at launch. **Biometric data never leaves the Secure Enclave of your iPhone** and is never transmitted to the App or to us. Apple exposes only a pass/fail boolean.

### 5. Photos and media library

If you enable photo sync, the App accesses your photo library only to upload the items you explicitly select, to the cloud service you configured. No photo is sent to any other recipient.

### 6. Files extension (File Provider)

The Apple Files extension shipped with the App operates in its own iOS sandbox. It holds only the permissions required to enumerate and materialize the files you ask to open.

### 7. Your rights (GDPR / CCPA)

Because no personal data is ever transmitted to us, there is nothing to delete, export, or rectify on our side. To revoke a cloud access, remove the authorization in that service's dashboard (e.g. `myaccount.google.com/permissions`).

### 8. Open source

The App embeds [rclone](https://rclone.org) (MIT) and several open-source libraries. The Rclone GUI source code is available on GitHub: <https://github.com/VitalysRDT/rclone-gui-ios>.

### 9. Contact

For any question regarding this privacy policy:

**Vitalys Rougetet — De Troyane**
Email: <vitalys@rougetet.com>
