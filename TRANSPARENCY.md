# Transparency — « 0 appel maison » (Glass Engine)

Rclone GUI ne téléphone à aucun serveur maison. Cette page explique comment le
**prouver**, côté développeur. Version grand public : `docs/transparency.html`
(rclone.rougetet.com/transparency.html).

## Ce que l'app contacte (et rien d'autre)

| Destination | Pourquoi | Catégorie |
|---|---|---|
| Vos remotes cloud (S3, Drive, B2, SFTP…) | Cœur de l'app, via rclone, HTTPS (ATS on) | vos remotes |
| Endpoints OAuth des fournisseurs (`accounts.google.com`, `login.microsoftonline.com`…) | Ajout d'un remote — PKCE, session web éphémère, **sans broker** (`OAuthBrokerService.swift`) | fournisseurs |
| Apple (`apps.apple.com`, StoreKit, iCloud KVS) | Abonnement, offer codes, ancre d'essai | Apple |
| `127.0.0.1` | Pont rclone loopback (`RcloneStreamingService`) — ne quitte pas l'appareil | sur l'appareil |

**Absents :** aucun SDK analytics/crash/pub · pas de push distant (aucun
`registerForRemoteNotifications`, pas d'APNs/device token) · pas de serveur dorsal ·
pas de serveur de licence. `rougetet.com` n'est **jamais appelé** (uniquement lié → Safari).

## Moniteur in-app

`Rclone GUI/Core/GlassEngine.swift` :
- `GlassEngine` (pur, `nonisolated`) : allowlist dérivée de `BackendOverrides.oauthConfigs`,
  `classify(host:)` (fail-closed → `.home`), denylists, `verdict()`.
- `GlassEngineMonitor` (`@MainActor`, `ObservableObject`) : bus passif, `record(host:purpose:)`
  non bloquant appelé depuis les call-sites (OAuth token/authorize, pont loopback).

Écran : Réglages → **Transparence** (`Rclone GUI/Views/Settings/GlassEngineView.swift`).

## Vérifier soi-même

**Au proxy** — router l'app via mitmproxy/Charles/Proxyman : on ne voit que remotes +
OAuth fournisseurs + Apple + loopback. Aucun `rougetet.com` / `vercel` / `supabase` / analytics.

**Garde source (rapide, en CI sur chaque commit) :**
```bash
./scripts/verify-no-phone-home.sh
```
Échoue si un SDK de tracking ou un endpoint maison apparaît dans le code Swift.

**Build reproductible du framework natif rclone :**
```bash
./scripts/build-rclone.sh          # rclone v1.74.3 + gomobile épinglés, -trimpath, -buildid=
./scripts/verify-reproducible.sh   # compare aux empreintes committées + garde source
```
Manifeste : `Frameworks/RcloneKit.xcframework.sha256`. Régénération mainteneur :
`./scripts/verify-reproducible.sh --record` après un build propre.

Toolchain de référence : Xcode 27.0 (`.xcode-version`), Go 1.26, rclone v1.74.3.
CI : job `transparency-guard` (chaque PR) + `reproducible-build` (`workflow_dispatch`).

> Honnêteté : librclone (Go) fait son réseau vers *vos* remotes hors du moniteur
> URLSession. On le **déclare** depuis `config/dump` plutôt que de le simuler ; il reste
> vérifiable au proxy. gomobile n'est pas garanti bit-à-bit sur toute machine — les
> empreintes canoniques viennent du build mainteneur, les flags déterministes minimisent l'écart.
