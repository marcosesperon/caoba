#!/bin/sh
# Compila CAOBA en Release como binario universal (Apple Silicon + Intel),
# crea el DMG y, con --publish, lo sube a una release de GitHub.
#
# Uso:
#   Tools/make-release.sh              # solo compila y crea dist/CAOBA-<version>.dmg
#   Tools/make-release.sh --publish    # ademas crea la etiqueta v<version> y la release en GitHub
#
# La version se lee de MARKETING_VERSION en project.yml.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
[ -n "$VERSION" ] || { echo "No encuentro MARKETING_VERSION en project.yml" >&2; exit 1; }
TAG="v$VERSION"
DERIVED="build/ReleaseBuild"
APP="$DERIVED/Build/Products/Release/CAOBA.app"
DIST="dist"
DMG="$DIST/CAOBA-$VERSION.dmg"
PUBLISH=0
[ "${1:-}" = "--publish" ] && PUBLISH=1

# Xcode: si xcode-select apunta a las Command Line Tools, usamos la app.
if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "== CAOBA $VERSION =="
command -v xcodegen >/dev/null || { echo "Falta xcodegen (brew install xcodegen)" >&2; exit 1; }
[ -d CaobaApp/Vendor/exiftool ] || echo "Aviso: no hay exiftool en CaobaApp/Vendor (Tools/fetch-exiftool.sh); Shutter Count solo leera Nikon."

echo "-- Tests del motor"
(cd CaobaCore && swift test --parallel 2>&1 | tail -1)

echo "-- Proyecto"
xcodegen generate >/dev/null

echo "-- Compilando universal (arm64 + x86_64)"
rm -rf "$DERIVED"
xcodebuild -project CAOBA.xcodeproj -scheme CAOBA -configuration Release \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | grep -E "error:|BUILD" || true
[ -d "$APP" ] || { echo "No se ha generado la app" >&2; exit 1; }
lipo -info "$APP/Contents/MacOS/CAOBA"

# Firma: con CAOBA_SIGN_IDENTITY (p. ej. "Developer ID Application: Nombre (EQUIPO)") se firma
# con ese certificado y hardened runtime; sin ella, firma ad hoc como hasta ahora.
if [ -n "${CAOBA_SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$CAOBA_SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP" && echo "Firma Developer ID correcta"
else
  codesign --force --deep --sign - "$APP" 2>/dev/null
  codesign --verify --deep --strict "$APP" && echo "Firma ad hoc correcta"
fi

echo "-- DMG"
mkdir -p "$DIST"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "CAOBA $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
du -h "$DMG"

# Notarizacion: con CAOBA_NOTARY_PROFILE (perfil guardado con `xcrun notarytool store-credentials`)
# se envia el DMG a Apple, se espera el resultado y se grapa el ticket.
if [ -n "${CAOBA_SIGN_IDENTITY:-}" ] && [ -n "${CAOBA_NOTARY_PROFILE:-}" ]; then
  echo "-- Notarizando"
  xcrun notarytool submit "$DMG" --keychain-profile "$CAOBA_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

if [ "$PUBLISH" = "1" ]; then
  echo "-- Publicando $TAG"
  [ -z "$(git status --porcelain)" ] || { echo "Hay cambios sin commitear; publica desde un arbol limpio." >&2; exit 1; }
  if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    git tag -a "$TAG" -m "CAOBA $VERSION"
    git push origin "$TAG"
  fi
  # Las notas salen de la seccion de esta version en CHANGELOG.md; sin seccion no se publica.
  NOTES="$(awk -v v="$VERSION" '/^## /{p = ($2 == v)} p && !/^## /' CHANGELOG.md | sed '/^[[:space:]]*$/d')"
  [ -n "$NOTES" ] || { echo "CHANGELOG.md no tiene seccion para $VERSION" >&2; exit 1; }
  gh release create "$TAG" "$DMG" --title "CAOBA $VERSION" --notes "$NOTES"
  echo "Release publicada: $(gh release view "$TAG" --json url --jq .url)"
fi
