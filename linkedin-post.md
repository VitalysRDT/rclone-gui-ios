# 🚀 Kit de lancement LinkedIn — Rclone GUI

> **Format conseillé :** un **Post** natif + un **visuel** (vidéo 25 s ou carrousel Documents).
> **Offre vedette :** 1 mois offert via un code App Store perso (un par personne, stocks limités) sur **rclone.rougetet.com**.

---

## ⚙️ Avant de publier (LinkedIn ne lit pas le Markdown)

- Le composeur LinkedIn est en **texte brut** : `**gras**`, `# titres` et `[texte](url)` ne sont **pas** rendus.
- **Gras réel** → convertir en caractères Unicode (yaytext.com, etc.) si besoin.
- **Lien** → coller l'URL nue `https://rclone.rougetet.com` (LinkedIn génère la carte aperçu). Pour préserver le reach, possibilité de mettre le lien en **premier commentaire**.
- **Listes / titres** → garder les emojis et `•` (ils passent en texte brut).
- Ce fichier est ton brouillon : copie le bloc voulu, puis « aplatis » le formatage au collage.

---

## 1) Post principal — 🇫🇷 Français

🚀 J'ai publié **Rclone GUI** sur l'App Store — un client cloud natif iOS & macOS, pensé pour ceux qui veulent reprendre le contrôle de leurs données.

🎁 Pour fêter ça : **1 mois offert**. Récupérez votre code App Store perso (un clic, un par personne) sur 👉 rclone.rougetet.com

L'idée : rclone est l'outil de référence pour gérer ses stockages cloud… mais il vit dans un terminal. Je voulais une vraie app native, élégante et **privacy-first**, qui parle directement à vos clouds — **sans aucun serveur intermédiaire**.

☁️ **80+ clouds dans une seule app**
S3, Cloudflare R2, Backblaze B2, Google Drive, OneDrive, Dropbox, Storj, Wasabi, pCloud, Mega, Box, Filen, Internxt, Drime, SFTP, WebDAV…

🔐 **Chiffrement de bout en bout (crypt-first)**
Remotes chiffrés rclone « crypt » natifs : noms déchiffrés à la volée, contenu déchiffré pendant la lecture, jamais en clair sur un serveur tiers (NaCl secretbox, local).

🛡️ **Confidentialité par conception**
Zéro analytics, zéro tracker, zéro SDK tiers. Config chiffrée au repos (ChaCha20-Poly1305 + Keychain), Face ID / Touch ID, ATS strict.

🎬 **Nouveautés v1.5**
• Vrai **lecteur vidéo embarqué multi-format** (MP4, MKV, AVI, WebM… moteur hybride AVPlayer + VLCKit), au choix dans l'app ou en externe
• **Galerie photos & vidéos en grille** avec miniatures en cache
• **Réglage pour exclure les données des sauvegardes iCloud**

📂 **Et aussi** : intégration app Fichiers iOS (File Provider), PhotoSync auto, streaming audio/vidéo (range requests), assistant d'ajout guidé (tutos OAuth), transferts parallèles, throttling adaptatif.

🛠️ **Côté technique**
• Swift / SwiftUI natif **iOS + macOS** (base unique)
• Le **vrai moteur rclone (Go)** compilé en framework natif via gomobile
• Cryptographie & sécurité (Keychain, Secure Enclave, ATS)
• File Provider + serveur HTTP loopback pour le streaming
• CI/CD : Xcode Cloud + fastlane, releases automatisées, **13 langues**
• 100 % **open source** (MPL-2.0)

👉 1 mois offert + téléchargement : **rclone.rougetet.com**

Vos retours et idées sont les bienvenus 🙌

#iOS #Swift #SwiftUI #macOS #CloudStorage #Privacy #OpenSource #rclone #IndieDev #Chiffrement #AppStore

---

## 2) Post principal — 🇬🇧 English

🚀 I just shipped **Rclone GUI** on the App Store — a native iOS & macOS cloud client for people who want to own their data again.

🎁 To celebrate: **one month free**. Grab your personal App Store code (one click, one per person) at 👉 rclone.rougetet.com

The idea: rclone is *the* reference tool to manage personal cloud storage… but it lives in a terminal. I wanted a real native app — elegant, **privacy-first**, talking straight to your clouds with **no middleman server**.

☁️ **80+ clouds in one app**
S3, Cloudflare R2, Backblaze B2, Google Drive, OneDrive, Dropbox, Storj, Wasabi, pCloud, Mega, Box, Filen, Internxt, Drime, SFTP, WebDAV…

🔐 **End-to-end encryption (crypt-first)**
Native rclone "crypt" remotes: filenames decrypted on the fly, content decrypted during playback, never in clear through a third-party server (NaCl secretbox, local).

🛡️ **Privacy by design**
No analytics, no tracker, no third-party SDK. Config encrypted at rest (ChaCha20-Poly1305 + Keychain), Face ID / Touch ID, strict ATS.

🎬 **New in v1.5**
• A real **embedded multi-format video player** (MP4, MKV, AVI, WebM… hybrid AVPlayer + VLCKit), in-app or external
• A **photo & video grid gallery** with cached thumbnails
• A **toggle to exclude data from iCloud backups**

📂 **Also**: iOS Files integration (File Provider), automatic PhotoSync, audio/video streaming (range requests), guided add-remote wizard (OAuth tutorials), parallel transfers, adaptive throttling.

🛠️ **Under the hood**
• Native Swift / SwiftUI for **iOS + macOS** (single codebase)
• The **real rclone engine (Go)** compiled to a native framework via gomobile
• Cryptography & security (Keychain, Secure Enclave, ATS)
• File Provider + loopback HTTP server for streaming
• CI/CD: Xcode Cloud + fastlane, automated releases, **13 languages**
• 100% **open source** (MPL-2.0)

👉 One month free + download: **rclone.rougetet.com**

Feedback and feature ideas welcome 🙌

#iOS #Swift #SwiftUI #macOS #CloudStorage #Privacy #OpenSource #rclone #IndieDev #Encryption #AppStore

---

## 3) Versions courtes

**🇫🇷 FR**

🚀 Nouveau : **Rclone GUI**, mon client cloud natif iOS & macOS. 🎁 **1 mois offert** — code perso sur le site.
80+ clouds (S3, R2, Drive, Dropbox, B2, SFTP…), **chiffré de bout en bout**, **sans serveur intermédiaire**. Intégration Fichiers iOS, PhotoSync, et (v1.5) **lecteur vidéo multi-format embarqué** + **galerie en grille**.
Stack : Swift/SwiftUI (iOS+macOS), moteur rclone Go via gomobile, open source MPL-2.0, 13 langues.
👉 **rclone.rougetet.com**
#iOS #Swift #Privacy #OpenSource #CloudStorage #rclone #IndieDev

**🇬🇧 EN**

🚀 New: **Rclone GUI**, my native iOS & macOS cloud client. 🎁 **One month free** — personal code on the site.
80+ clouds (S3, R2, Drive, Dropbox, B2, SFTP…), **end-to-end encrypted**, **no middleman server**. iOS Files integration, PhotoSync, and (v1.5) an **embedded multi-format video player** + **grid gallery**.
Stack: Swift/SwiftUI (iOS+macOS), Go rclone engine via gomobile, open source MPL-2.0, 13 languages.
👉 **rclone.rougetet.com**
#iOS #Swift #Privacy #OpenSource #CloudStorage #rclone #IndieDev

---

## 4) Premier commentaire (si tu mets le lien hors du post)

🔗 Lien + **1 mois offert** (code App Store perso, un par personne) : rclone.rougetet.com
⭐️ Open source : github.com/VitalysRDT/rclone-gui-ios

---

## 5) Carrousel « Documents » (PDF, 6 slides)

1. **Rclone GUI** — Vos 80+ clouds, chiffrés, dans une app iOS & macOS. 🎁 *1 mois offert*
2. **Privacy-first** — Aucun serveur intermédiaire · zéro tracker · config chiffrée localement · Face ID
3. **Chiffrement crypt** — Noms & contenus déchiffrés à la volée, jamais en clair côté serveur
4. **v1.5** — Lecteur vidéo multi-format embarqué (AVPlayer + VLCKit) + galerie média en grille
5. **Sous le capot** — SwiftUI iOS+macOS · vrai moteur rclone (Go/gomobile) · Xcode Cloud + fastlane · 13 langues · open source
6. **Essayez gratuitement** — 1 mois offert → rclone.rougetet.com

---

## 6) Script vidéo démo (~25 s)

- **0–3 s** — Ouverture de l'app, liste des remotes (montrer le cadenas violet « crypt »).
- **3–9 s** — Navigation dans un dossier → bascule **liste → grille** (galerie média, miniatures).
- **9–17 s** — Ouverture d'une **vidéo MKV** dans le **lecteur embarqué** (preuve du multi-format).
- **17–22 s** — Réglages : toggle **exclusion iCloud** + intégration **Fichiers iOS**.
- **22–25 s** — Carton final : « 1 mois offert — rclone.rougetet.com ».
