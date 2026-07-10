#!/usr/bin/env bash
#
# scripts/verify-no-phone-home.sh
#
# Glass Engine — garde « 0 appel maison » exécutée au build (rapide, sans
# compilation). Échoue si le code source Swift de l'app introduit :
#   1. un SDK de tracking / analytics / crash-reporting,
#   2. un endpoint de télémétrie ou de serveur dorsal,
#   3. un appel réseau vers rougetet.com (le site ne doit être QUE lié → Safari).
#
# C'est le pendant « durable au build » du moniteur in-app GlassEngine : la
# revendication « 0 appel maison » devient une invariante testée. La liste de
# référence vit dans Rclone GUI/Core/GlassEngine.swift (denylists).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Rclone GUI"
fail=0

# GlassEngine.swift contient volontairement les denylists (données) → exclu.
EXCLUDES=(--include='*.swift' --exclude=GlassEngine.swift)

echo "== Glass Engine — vérification « 0 appel maison » =="
echo "Source : $SRC"
echo ""

# 1) SDK de tracking interdits (forme `import X` pour éviter les faux positifs
#    sur des mots courants comme « branch », « segment », « adjust »).
TRACKING_IMPORTS='^[[:space:]]*import[[:space:]]+(Firebase|FirebaseAnalytics|FirebaseCrashlytics|Crashlytics|Sentry|Mixpanel|Amplitude|Segment|Bugsnag|AppCenter|AppCenterAnalytics|AppCenterCrashes|Flurry|Adjust|AppsFlyerLib|Branch|BranchSDK|OneSignal|OneSignalFramework|Datadog|DatadogCore|Instabug|Smartlook|TelemetryDeck|TelemetryClient|Heap|Countly|Matomo|GoogleAnalytics|GoogleAppMeasurement)([[:space:]]|$)'
if grep -rInE "$TRACKING_IMPORTS" "$SRC" "${EXCLUDES[@]}"; then
    echo "❌ SDK de tracking importé (ci-dessus)."
    fail=1
else
    echo "✅ Aucun SDK de tracking importé."
fi

# 2) Hosts de télémétrie / dorsal interdits comme cible réseau.
HOME_HOSTS='sentry\.io|supabase\.(co|in|com)|vercel\.app|firebaseio\.com|app-measurement\.com|crashlytics|mixpanel\.com|amplitude\.com|segment\.(io|com)|google-analytics\.com|googletagmanager\.com|bugsnag\.com|datadoghq\.com|appcenter\.ms|flurry\.com|adjust\.com|appsflyer\.com|branch\.io|onesignal\.com|instabug\.com|smartlook\.com'
if grep -rInE "$HOME_HOSTS" "$SRC" "${EXCLUDES[@]}"; then
    echo "❌ Endpoint télémétrie/dorsal détecté (ci-dessus)."
    fail=1
else
    echo "✅ Aucun endpoint télémétrie/dorsal."
fi

# 3) rougetet.com (le site vitrine) ne doit être QUE lié (Link/openURL → Safari),
#    jamais la cible d'un appel réseau. On cherche une co-occurrence SUR LA MÊME
#    ligne d'un host rougetet.com et d'un verbe d'appel réseau (les liens Safari
#    utilisent URL(string:)/Link/openURL — pas ces verbes).
NET_CALL='URLSession|URLRequest|dataTask|\.data\(from:|\.data\(for:|\.download\(from:|NWConnection'
if grep -rInE 'rougetet\.com' "$SRC" "${EXCLUDES[@]}" | grep -E "$NET_CALL"; then
    echo "❌ rougetet.com est la cible d'un appel réseau (ci-dessus)."
    fail=1
else
    echo "✅ rougetet.com uniquement lié (Safari), jamais appelé."
fi

echo ""
if [ "$fail" -ne 0 ]; then
    echo "ÉCHEC : la garde « 0 appel maison » a trouvé une violation."
    exit 1
fi
echo "OK : 0 appel maison — aucune violation détectée."
