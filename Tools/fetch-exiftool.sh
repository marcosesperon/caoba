#!/bin/sh
# Descarga la distribucion oficial de ExifTool (Perl) y la deja en
# CaobaApp/Vendor/exiftool, que el proyecto copia dentro de la app como recurso
# opcional. Sin esta carpeta la app funciona igual, pero Shutter Count solo
# lee el contador de Nikon (via ImageIO).
#
# Uso: Tools/fetch-exiftool.sh
set -eu

VERSION="13.59"
SHA256="668ea3acececb7235fbd0f4900e72d5f12c9b07e5c778fd36cb1e9b5828fd65a"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/CaobaApp/Vendor/exiftool"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$VERSION" ]; then
  echo "exiftool $VERSION ya esta en $DEST"
  exit 0
fi

echo "Descargando Image-ExifTool-$VERSION..."
# exiftool.org solo sirve la ultima version; el espejo de SourceForge conserva todas.
curl -sSL -o "$TMP/exiftool.tar.gz" \
  "https://sourceforge.net/projects/exiftool/files/Image-ExifTool-$VERSION.tar.gz/download" \
  || curl -sSL -o "$TMP/exiftool.tar.gz" "https://exiftool.org/Image-ExifTool-$VERSION.tar.gz"

echo "$SHA256  $TMP/exiftool.tar.gz" | shasum -a 256 -c - >/dev/null || {
  echo "La suma de comprobacion no coincide; descarga descartada." >&2
  exit 1
}

tar -xzf "$TMP/exiftool.tar.gz" -C "$TMP"
rm -rf "$DEST"
mkdir -p "$DEST"
cp "$TMP/Image-ExifTool-$VERSION/exiftool" "$DEST/exiftool"
cp -R "$TMP/Image-ExifTool-$VERSION/lib" "$DEST/lib"
cp "$TMP/Image-ExifTool-$VERSION/README" "$DEST/README"
chmod +x "$DEST/exiftool"
echo "$VERSION" > "$DEST/VERSION"
echo "exiftool $VERSION instalado en $DEST ($(du -sh "$DEST" | cut -f1))"
