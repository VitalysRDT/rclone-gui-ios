# LinkedIn — version GRAS UNICODE (prête à coller)

> Copie-colle directement : le gras est en caractères Unicode, donc visible sur LinkedIn.
> NB : les lettres accentuées (é, à, ç…) restent en style normal — c'est normal, l'alphabet gras Unicode ne les contient pas.

---

## 🇫🇷 Français

🚀 J'ai publié 𝗥𝗰𝗹𝗼𝗻𝗲 𝗚𝗨𝗜 sur l'App Store — un client cloud natif iOS & macOS, pensé pour ceux qui veulent reprendre le contrôle de leurs données.

🎁 Pour fêter ça : 𝟭 𝗺𝗼𝗶𝘀 𝗼𝗳𝗳𝗲𝗿𝘁. Récupérez votre code App Store perso (un clic, un par personne) sur 👉 rclone.rougetet.com

L'idée : rclone est l'outil de référence pour gérer ses stockages cloud… mais il vit dans un terminal. Je voulais une vraie app native, élégante et 𝗽𝗿𝗶𝘃𝗮𝗰𝘆-𝗳𝗶𝗿𝘀𝘁, qui parle directement à vos clouds — 𝘀𝗮𝗻𝘀 𝗮𝘂𝗰𝘂𝗻 𝘀𝗲𝗿𝘃𝗲𝘂𝗿 𝗶𝗻𝘁𝗲𝗿𝗺é𝗱𝗶𝗮𝗶𝗿𝗲.

☁️ 𝟴𝟬+ 𝗰𝗹𝗼𝘂𝗱𝘀 𝗱𝗮𝗻𝘀 𝘂𝗻𝗲 𝘀𝗲𝘂𝗹𝗲 𝗮𝗽𝗽
S3, Cloudflare R2, Backblaze B2, Google Drive, OneDrive, Dropbox, Storj, Wasabi, pCloud, Mega, Box, Filen, Internxt, Drime, SFTP, WebDAV…

🔐 𝗖𝗵𝗶𝗳𝗳𝗿𝗲𝗺𝗲𝗻𝘁 𝗱𝗲 𝗯𝗼𝘂𝘁 𝗲𝗻 𝗯𝗼𝘂𝘁 (𝗰𝗿𝘆𝗽𝘁-𝗳𝗶𝗿𝘀𝘁)
Remotes chiffrés rclone « crypt » natifs : noms déchiffrés à la volée, contenu déchiffré pendant la lecture, jamais en clair sur un serveur tiers (NaCl secretbox, local).

🛡️ 𝗖𝗼𝗻𝗳𝗶𝗱𝗲𝗻𝘁𝗶𝗮𝗹𝗶𝘁é 𝗽𝗮𝗿 𝗰𝗼𝗻𝗰𝗲𝗽𝘁𝗶𝗼𝗻
Zéro analytics, zéro tracker, zéro SDK tiers. Config chiffrée au repos (ChaCha20-Poly1305 + Keychain), Face ID / Touch ID, ATS strict.

🎬 𝗡𝗼𝘂𝘃𝗲𝗮𝘂𝘁é𝘀 𝘃𝟭.𝟱
• Vrai 𝗹𝗲𝗰𝘁𝗲𝘂𝗿 𝘃𝗶𝗱é𝗼 𝗲𝗺𝗯𝗮𝗿𝗾𝘂é 𝗺𝘂𝗹𝘁𝗶-𝗳𝗼𝗿𝗺𝗮𝘁 (MP4, MKV, AVI, WebM… moteur hybride AVPlayer + VLCKit), au choix dans l'app ou en externe
• 𝗚𝗮𝗹𝗲𝗿𝗶𝗲 𝗽𝗵𝗼𝘁𝗼𝘀 & 𝘃𝗶𝗱é𝗼𝘀 𝗲𝗻 𝗴𝗿𝗶𝗹𝗹𝗲 avec miniatures en cache
• 𝗥é𝗴𝗹𝗮𝗴𝗲 𝗽𝗼𝘂𝗿 𝗲𝘅𝗰𝗹𝘂𝗿𝗲 𝗹𝗲𝘀 𝗱𝗼𝗻𝗻é𝗲𝘀 𝗱𝗲𝘀 𝘀𝗮𝘂𝘃𝗲𝗴𝗮𝗿𝗱𝗲𝘀 𝗶𝗖𝗹𝗼𝘂𝗱

📂 𝗘𝘁 𝗮𝘂𝘀𝘀𝗶 : intégration app Fichiers iOS (File Provider), PhotoSync auto, streaming audio/vidéo (range requests), assistant d'ajout guidé (tutos OAuth), transferts parallèles, throttling adaptatif.

🛠️ 𝗖ô𝘁é 𝘁𝗲𝗰𝗵𝗻𝗶𝗾𝘂𝗲
• Swift / SwiftUI natif 𝗶𝗢𝗦 + 𝗺𝗮𝗰𝗢𝗦 (base unique)
• Le 𝘃𝗿𝗮𝗶 𝗺𝗼𝘁𝗲𝘂𝗿 𝗿𝗰𝗹𝗼𝗻𝗲 (𝗚𝗼) compilé en framework natif via gomobile
• Cryptographie & sécurité (Keychain, Secure Enclave, ATS)
• File Provider + serveur HTTP loopback pour le streaming
• CI/CD : Xcode Cloud + fastlane, releases automatisées, 𝟭𝟯 𝗹𝗮𝗻𝗴𝘂𝗲𝘀
• 100 % 𝗼𝗽𝗲𝗻 𝘀𝗼𝘂𝗿𝗰𝗲 (MPL-2.0)

👉 1 mois offert + téléchargement : 𝗿𝗰𝗹𝗼𝗻𝗲.𝗿𝗼𝘂𝗴𝗲𝘁𝗲𝘁.𝗰𝗼𝗺

Vos retours et idées sont les bienvenus 🙌

#iOS #Swift #SwiftUI #macOS #CloudStorage #Privacy #OpenSource #rclone #IndieDev #Chiffrement #AppStore

---

## 🇬🇧 English

🚀 I just shipped 𝗥𝗰𝗹𝗼𝗻𝗲 𝗚𝗨𝗜 on the App Store — a native iOS & macOS cloud client for people who want to own their data again.

🎁 To celebrate: 𝗼𝗻𝗲 𝗺𝗼𝗻𝘁𝗵 𝗳𝗿𝗲𝗲. Grab your personal App Store code (one click, one per person) at 👉 rclone.rougetet.com

The idea: rclone is *the* reference tool to manage personal cloud storage… but it lives in a terminal. I wanted a real native app — elegant, 𝗽𝗿𝗶𝘃𝗮𝗰𝘆-𝗳𝗶𝗿𝘀𝘁, talking straight to your clouds with 𝗻𝗼 𝗺𝗶𝗱𝗱𝗹𝗲𝗺𝗮𝗻 𝘀𝗲𝗿𝘃𝗲𝗿.

☁️ 𝟴𝟬+ 𝗰𝗹𝗼𝘂𝗱𝘀 𝗶𝗻 𝗼𝗻𝗲 𝗮𝗽𝗽
S3, Cloudflare R2, Backblaze B2, Google Drive, OneDrive, Dropbox, Storj, Wasabi, pCloud, Mega, Box, Filen, Internxt, Drime, SFTP, WebDAV…

🔐 𝗘𝗻𝗱-𝘁𝗼-𝗲𝗻𝗱 𝗲𝗻𝗰𝗿𝘆𝗽𝘁𝗶𝗼𝗻 (𝗰𝗿𝘆𝗽𝘁-𝗳𝗶𝗿𝘀𝘁)
Native rclone "crypt" remotes: filenames decrypted on the fly, content decrypted during playback, never in clear through a third-party server (NaCl secretbox, local).

🛡️ 𝗣𝗿𝗶𝘃𝗮𝗰𝘆 𝗯𝘆 𝗱𝗲𝘀𝗶𝗴𝗻
No analytics, no tracker, no third-party SDK. Config encrypted at rest (ChaCha20-Poly1305 + Keychain), Face ID / Touch ID, strict ATS.

🎬 𝗡𝗲𝘄 𝗶𝗻 𝘃𝟭.𝟱
• A real 𝗲𝗺𝗯𝗲𝗱𝗱𝗲𝗱 𝗺𝘂𝗹𝘁𝗶-𝗳𝗼𝗿𝗺𝗮𝘁 𝘃𝗶𝗱𝗲𝗼 𝗽𝗹𝗮𝘆𝗲𝗿 (MP4, MKV, AVI, WebM… hybrid AVPlayer + VLCKit), in-app or external
• A 𝗽𝗵𝗼𝘁𝗼 & 𝘃𝗶𝗱𝗲𝗼 𝗴𝗿𝗶𝗱 𝗴𝗮𝗹𝗹𝗲𝗿𝘆 with cached thumbnails
• A 𝘁𝗼𝗴𝗴𝗹𝗲 𝘁𝗼 𝗲𝘅𝗰𝗹𝘂𝗱𝗲 𝗱𝗮𝘁𝗮 𝗳𝗿𝗼𝗺 𝗶𝗖𝗹𝗼𝘂𝗱 𝗯𝗮𝗰𝗸𝘂𝗽𝘀

📂 𝗔𝗹𝘀𝗼: iOS Files integration (File Provider), automatic PhotoSync, audio/video streaming (range requests), guided add-remote wizard (OAuth tutorials), parallel transfers, adaptive throttling.

🛠️ 𝗨𝗻𝗱𝗲𝗿 𝘁𝗵𝗲 𝗵𝗼𝗼𝗱
• Native Swift / SwiftUI for 𝗶𝗢𝗦 + 𝗺𝗮𝗰𝗢𝗦 (single codebase)
• The 𝗿𝗲𝗮𝗹 𝗿𝗰𝗹𝗼𝗻𝗲 𝗲𝗻𝗴𝗶𝗻𝗲 (𝗚𝗼) compiled to a native framework via gomobile
• Cryptography & security (Keychain, Secure Enclave, ATS)
• File Provider + loopback HTTP server for streaming
• CI/CD: Xcode Cloud + fastlane, automated releases, 𝟭𝟯 𝗹𝗮𝗻𝗴𝘂𝗮𝗴𝗲𝘀
• 100% 𝗼𝗽𝗲𝗻 𝘀𝗼𝘂𝗿𝗰𝗲 (MPL-2.0)

👉 One month free + download: 𝗿𝗰𝗹𝗼𝗻𝗲.𝗿𝗼𝘂𝗴𝗲𝘁𝗲𝘁.𝗰𝗼𝗺

Feedback and feature ideas welcome 🙌

#iOS #Swift #SwiftUI #macOS #CloudStorage #Privacy #OpenSource #rclone #IndieDev #Encryption #AppStore
