#!/bin/bash
# Mise à jour sûre du fork Adrafinil depuis kageroumado/adrafinil (la mise à jour automatique est
# coupée dans ce fork, voir SilentUpdates.isEnabled).
#
#   scripts/update-from-upstream.sh preview         # défaut : ce qui a changé en amont, rien n'est modifié
#   scripts/update-from-upstream.sh apply <commit>  # le commit amont RELU : rebase, tests, build, installation
#
# `preview` écrit le diff complet de l'amont (zones sensibles en tête) dans tasks/ et affiche le
# commit à relire. `apply` refuse tout autre commit : l'amont ne peut pas changer entre la relecture
# et l'installation. `swift test` et le build exécutent le code de l'amont : la relecture d'abord.
# `apply` dure plusieurs minutes : le lancer depuis Claude, pas avec « ! » (coupé à 120 s).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

BRANCH="victor/veille-capot"
TEAM="H768Z5W6LX"
UPSTREAM_URL="https://github.com/kageroumado/adrafinil.git"
MODE="${1:-preview}"
REVIEWED="${2:-}"
STAMP="$(date +%Y%m%d-%H%M)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adrafinil-update.XXXXXX")"
SENSITIVE=(AdrafinilHelper AdrafinilDaemon AdrafinilCLI AdrafinilShared/Package.swift
  AdrafinilShared/Sources/AdrafinilShared/IPC AdrafinilShared/Sources/AdrafinilShared/Installer
  Adrafinil.xcodeproj Adrafinil/Adrafinil.entitlements .githooks .github scripts)

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

die() { echo "ERREUR : $*" >&2; exit 1; }

[ "$(git rev-parse --abbrev-ref HEAD)" = "$BRANCH" ] || die "pas sur la branche $BRANCH"
[ "$(git remote get-url upstream)" = "$UPSTREAM_URL" ] || die "remote upstream inattendu : $(git remote get-url upstream)"

echo "==> 1/2 Récupération de l'amont"
git fetch -q upstream
TARGET="$(git rev-parse upstream/main)"
BASE="$(git merge-base HEAD "$TARGET")"
NEW="$(git rev-list --count "$BASE..$TARGET")"
echo "    $NEW commit(s) en amont depuis $(git log -1 --format='%h %cs' "$BASE")"
if [ "$NEW" -eq 0 ]; then echo "Rien à mettre à jour."; exit 0; fi

echo "==> 2/2 Ce qui change"
git log --format='    %h %cs %an  %s' "$BASE..$TARGET" | head -40
echo
echo "    Zones sensibles touchées :"
git diff --stat "$BASE" "$TARGET" -- "${SENSITIVE[@]}" | sed 's/^/      /'
SCRIPT_PHASES="$(git diff "$BASE" "$TARGET" -- Adrafinil.xcodeproj/project.pbxproj | grep -c 'shellScript' || true)"
[ "$SCRIPT_PHASES" -eq 0 ] || echo "    ⚠ une phase « Run Script » est ajoutée ou modifiée dans le projet Xcode"
mkdir -p "$REPO/tasks"
REVIEW="$REPO/tasks/upstream-review-${TARGET:0:12}.diff"
{ git diff "$BASE" "$TARGET" -- "${SENSITIVE[@]}"; git diff "$BASE" "$TARGET" -- . "${SENSITIVE[@]/#/:!}"; } > "$REVIEW"
echo "    Diff complet à relire (zones sensibles en tête) : $REVIEW ($(wc -l < "$REVIEW" | tr -d ' ') lignes)"

if [ "$MODE" != "apply" ]; then
  echo
  echo "Récapitulatif : $NEW commit(s) en amont, rien n'a été modifié."
  echo "Après relecture : $0 apply $TARGET"
  exit 0
fi

[ "$REVIEWED" = "$TARGET" ] || die "l'amont relu ($REVIEWED) n'est pas l'amont actuel ($TARGET) : relancer preview"

echo
echo "==> apply 1/5 Rebase sur $TARGET (sauvegarde : backup/$BRANCH-$STAMP)"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "arbre de travail modifié : committer d'abord"
git branch "backup/$BRANCH-$STAMP"
git rebase "$TARGET" || die "conflit de rebase : le résoudre, ou « git rebase --abort » pour revenir en arrière"

echo "==> apply 2/5 Tests"
swift test --package-path AdrafinilShared > "$WORK/test.log" 2>&1 || { grep -E '✘' "$WORK/test.log" | head; die "tests en échec"; }
grep -E 'Test run with' "$WORK/test.log" | sed 's/^/    /'

echo "==> apply 3/5 Build Release signé (équipe $TEAM, sans get-task-allow)"
xcodebuild -project Adrafinil.xcodeproj -scheme Adrafinil -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$WORK/dd" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp" build > "$WORK/build.log" 2>&1 \
  || { grep -E 'error:' "$WORK/build.log" | head -20; die "build en échec"; }
APP="$WORK/dd/Build/Products/Release/Adrafinil.app"

echo "==> apply 4/5 Vérifications de signature"
codesign --verify --deep --strict "$APP" || die "signature invalide"
check() { # binaire, identifiant attendu
  local info; info="$(codesign -dv "$1" 2>&1)"
  grep -q "TeamIdentifier=$TEAM" <<< "$info" || die "équipe inattendue : $1"
  grep -q "^Identifier=$2\$" <<< "$info" || die "identifiant inattendu (attendu $2) : $1"
  local ents; ents="$(codesign -d --entitlements - --xml "$1" 2>/dev/null || true)"
  if grep -q 'get-task-allow' <<< "$ents"; then die "get-task-allow présent : $1"; fi
}
check "$APP" glass.kagerou.adrafinil
check "$APP/Contents/Library/LaunchDaemons/AdrafinilHelper" AdrafinilHelper
check "$APP/Contents/Library/LaunchAgents/AdrafinilDaemon" AdrafinilDaemon
check "$APP/Contents/Helpers/adrafinil" adrafinil
echo "    4 binaires signés $TEAM, identifiants attendus, sans get-task-allow"

echo "==> apply 5/5 Installation (échange atomique, l'ancienne version gardée jusqu'au bout)"
STAGED="/Applications/.Adrafinil.app.new-$STAMP"
ditto "$APP" "$STAGED"
codesign --verify --deep --strict "$STAGED" || { rm -rf "$STAGED"; die "copie invalide"; }
osascript -e 'tell application "Adrafinil" to quit' 2>/dev/null || true
sleep 2
OLD="/Applications/.Adrafinil.app.old-$STAMP"
[ -d /Applications/Adrafinil.app ] && mv /Applications/Adrafinil.app "$OLD"
mv "$STAGED" /Applications/Adrafinil.app
rm -rf "$OLD"
open /Applications/Adrafinil.app

echo
echo "Récapitulatif : $NEW commit(s) intégrés ($TARGET), tests verts, build signé $TEAM, installé."
echo "Quitter l'app a relâché les maintiens en cours : chaque session est de nouveau tenue éveillée à son prochain message."
echo "Pousser la branche : git push --force-with-lease origin $BRANCH"
