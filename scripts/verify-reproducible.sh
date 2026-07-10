#!/usr/bin/env bash
#
# scripts/verify-reproducible.sh
#
# Glass Engine — vérifie que le framework natif rclone (RcloneKit.xcframework)
# qui entre dans l'app correspond aux empreintes SHA-256 committées, et lance la
# garde « 0 appel maison ». Permet à un tiers de PROUVER ce qui est dans le
# binaire.
#
# Usage :
#   scripts/verify-reproducible.sh            # vérifie le framework local vs le manifeste
#   scripts/verify-reproducible.sh --rebuild  # reconstruit d'abord via build-rclone.sh (~20 min)
#   scripts/verify-reproducible.sh --record   # (mainteneur) réécrit le manifeste depuis le framework local
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCF="$ROOT/Frameworks/RcloneKit.xcframework"
MANIFEST="$ROOT/Frameworks/RcloneKit.xcframework.sha256"

# Tranches canoniques (produites par build-rclone.sh par défaut).
ios_bin="$XCF/ios-arm64/RcloneKit.framework/RcloneKit"
mac_bin="$XCF/macos-arm64/RcloneKit.framework/Versions/A/RcloneKit"
slice_bin() {
    case "$1" in
        ios-arm64)   echo "$ios_bin" ;;
        macos-arm64) echo "$mac_bin" ;;
        *)           echo "" ;;
    esac
}

hash_of() { shasum -a 256 "$1" | awk '{print $1}'; }

case "${1:-}" in
    --rebuild)
        echo "Reconstruction déterministe via build-rclone.sh…"
        "$ROOT/scripts/build-rclone.sh"
        ;;
    --record)
        echo "Écriture du manifeste depuis le framework local…"
        {
            echo "# Glass Engine — empreintes SHA-256 du framework natif rclone (RcloneKit.xcframework)"
            echo "# Régénéré par scripts/verify-reproducible.sh --record après un build-rclone.sh propre."
            echo "# format : <slice>  <sha256>"
            for s in ios-arm64 macos-arm64; do
                printf '%s  %s\n' "$s" "$(hash_of "$(slice_bin "$s")")"
            done
        } > "$MANIFEST"
        echo "Manifeste écrit :"
        cat "$MANIFEST"
        exit 0
        ;;
esac

# 1) Garde source « 0 appel maison ».
"$ROOT/scripts/verify-no-phone-home.sh"

# 2) Comparaison des empreintes.
echo ""
echo "== Vérification des empreintes RcloneKit.xcframework =="
[ -e "$XCF" ]      || { echo "❌ Framework absent : $XCF (lancez --rebuild)"; exit 1; }
[ -f "$MANIFEST" ] || { echo "❌ Manifeste absent : $MANIFEST"; exit 1; }

fail=0
while read -r slice want _rest; do
    case "$slice" in ''|\#*) continue ;; esac
    bin="$(slice_bin "$slice")"
    [ -n "$bin" ] || continue
    if [ ! -f "$bin" ]; then
        echo "❌ $slice : binaire absent ($bin)"
        fail=1
        continue
    fi
    got="$(hash_of "$bin")"
    if [ "$got" = "$want" ]; then
        echo "✅ $slice  $got"
    else
        echo "❌ $slice  attendu $want  obtenu $got"
        fail=1
    fi
done < "$MANIFEST"

echo ""
if [ "$fail" -ne 0 ]; then
    echo "ÉCHEC : le framework ne correspond pas au manifeste committé."
    echo "Note : gomobile n'est pas garanti bit-à-bit sur toutes les machines ;"
    echo "les empreintes canoniques proviennent du build du mainteneur (voir docs/transparency.html)."
    exit 1
fi
echo "OK : le framework natif correspond aux empreintes committées."
