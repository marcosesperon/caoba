#!/bin/sh
# Compila PhotoRec (de TestDisk, GPL v2+) desde el codigo fuente como binario
# universal (arm64 + x86_64) y lo deja en CaobaApp/Vendor/photorec, que el
# proyecto copia dentro de la app como recurso opcional. Sin esta carpeta la
# app se compila igual, pero el modulo «Recuperar fotos» no puede funcionar.
#
# Se compila en modo solo linea de comandos (sin ncurses ni Qt), con libjpeg
# (IJG, licencia permisiva) enlazada de forma estatica para que PhotoRec
# compruebe y corte bien los JPG danados. Sin ntfs-3g ni e2fsprogs: el modo
# «solo espacio libre» funciona con FAT y exFAT (codigo propio de PhotoRec).
#
# Se aplica un cambio propio, Tools/photorec-fd.patch: si el dispositivo es
# /dev/fd/N (la tarjeta que abre authopen con la contraseña), PhotoRec duplica
# ese descriptor en vez de abrir la ruta, porque macOS volveria a comprobar los
# permisos del dispositivo (de root) y daria «Permission denied».
#
# Junto al binario (dentro de la app) deja:
#   VERSION          version de TestDisk
#   COPYING          licencia GPL de TestDisk
#   LICENSE-libjpeg  licencia de libjpeg (README de la IJG)
# Y en CaobaApp/Vendor/photorec-source (fuera de la app) el codigo fuente exacto
# de TestDisk y libjpeg, mas el parche, que Tools/make-release.sh adjunta a cada release.
#
# Uso: Tools/build-photorec.sh
set -eu

TESTDISK_VERSION="7.2"
TESTDISK_SHA256="f8343be20cb4001c5d91a2e3bcd918398f00ae6d8310894a5a9f2feb813c283f"
JPEG_VERSION="v9f"
JPEG_SHA256="04705c110cb2469caa79fb71fba3d7bf834914706e9641a4589485c1f832565b"
# Misma version minima que la app (project.yml).
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/Tools/photorec-fd.patch"
DEST="$ROOT/CaobaApp/Vendor/photorec"
SOURCES="$ROOT/CaobaApp/Vendor/photorec-source"
WORK="$ROOT/build/photorec"
TESTDISK_TAR="testdisk-$TESTDISK_VERSION.tar.bz2"
JPEG_TAR="jpegsrc.$JPEG_VERSION.tar.gz"

if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$TESTDISK_VERSION" ] && [ -x "$DEST/photorec" ] &&
   [ -f "$SOURCES/$TESTDISK_TAR" ] && cmp -s "$PATCH" "$SOURCES/photorec-fd.patch"; then
  echo "PhotoRec $TESTDISK_VERSION ya esta en $DEST"
  exit 0
fi

# Xcode: si xcode-select apunta a las Command Line Tools, usamos la app.
if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

rm -rf "$WORK"
mkdir -p "$WORK/src"

# Descarga un fichero y comprueba su suma; si no coincide, para.
download() {
  url="$1"; file="$2"; sum="$3"
  echo "Descargando $file..."
  curl -sSL -o "$WORK/src/$file" "$url"
  echo "$sum  $WORK/src/$file" | shasum -a 256 -c - >/dev/null || {
    echo "La suma de comprobacion de $file no coincide; descarga descartada." >&2
    exit 1
  }
}

download "https://www.cgsecurity.org/$TESTDISK_TAR" "$TESTDISK_TAR" "$TESTDISK_SHA256"
download "https://www.ijg.org/files/$JPEG_TAR" "$JPEG_TAR" "$JPEG_SHA256"

# Compila libjpeg y PhotoRec para una arquitectura y deja el binario en $WORK/<arch>/photorec.
build_arch() {
  arch="$1"; host="$2"
  echo "-- Compilando para $arch"
  dir="$WORK/$arch"
  mkdir -p "$dir"
  flags="-arch $arch -mmacosx-version-min=$MIN_MACOS -O2"

  # libjpeg estatica, instalada en una carpeta propia de esta arquitectura.
  tar xzf "$WORK/src/$JPEG_TAR" -C "$dir"
  (cd "$dir/jpeg-${JPEG_VERSION#v}" &&
    CFLAGS="$flags" ./configure --host="$host" --prefix="$dir/jpeg" \
      --disable-shared --enable-static >"$dir/jpeg-configure.log" 2>&1 &&
    make -j"$(sysctl -n hw.ncpu)" >"$dir/jpeg-make.log" 2>&1 &&
    make install >>"$dir/jpeg-make.log" 2>&1) || {
    echo "Fallo al compilar libjpeg ($arch); mira $dir/jpeg-*.log" >&2
    exit 1
  }

  # PhotoRec solo linea de comandos: sin ncurses, Qt, ntfs, ext2fs, ewf ni reiserfs.
  tar xjf "$WORK/src/$TESTDISK_TAR" -C "$dir"
  patch -s -p1 -d "$dir/testdisk-$TESTDISK_VERSION" <"$PATCH" || {
    echo "No se pudo aplicar $PATCH" >&2
    exit 1
  }
  (cd "$dir/testdisk-$TESTDISK_VERSION" &&
    CFLAGS="$flags" LDFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS" ./configure --host="$host" \
      --disable-qt --without-ncurses --without-ntfs --without-ntfs3g --without-ext2fs \
      --without-ewf --without-reiserfs \
      --with-jpeg-includes="$dir/jpeg/include" --with-jpeg-lib="$dir/jpeg/lib" \
      >"$dir/testdisk-configure.log" 2>&1 &&
    make -j"$(sysctl -n hw.ncpu)" -C src photorec >"$dir/testdisk-make.log" 2>&1) || {
    echo "Fallo al compilar PhotoRec ($arch); mira $dir/testdisk-*.log" >&2
    exit 1
  }
  cp "$dir/testdisk-$TESTDISK_VERSION/src/photorec" "$dir/photorec"
}

build_arch arm64 aarch64-apple-darwin
build_arch x86_64 x86_64-apple-darwin

echo "-- Binario universal"
rm -rf "$DEST" "$SOURCES"
mkdir -p "$DEST" "$SOURCES"
lipo -create "$WORK/arm64/photorec" "$WORK/x86_64/photorec" -output "$DEST/photorec"
lipo -info "$DEST/photorec"
# Comprueba que no depende de librerias de fuera del sistema (Homebrew, etc.).
if otool -L "$DEST/photorec" | grep -E "^[[:space:]]+/" | grep -v -E "^[[:space:]]+/(usr/lib|System)/" >/dev/null; then
  echo "PhotoRec enlaza librerias que no son del sistema:" >&2
  otool -L "$DEST/photorec" >&2
  exit 1
fi

# Licencias, version y codigo fuente exacto para cumplir la GPL.
echo "$TESTDISK_VERSION" >"$DEST/VERSION"
cp "$WORK/arm64/testdisk-$TESTDISK_VERSION/COPYING" "$DEST/COPYING"
cp "$WORK/arm64/jpeg-${JPEG_VERSION#v}/README" "$DEST/LICENSE-libjpeg"
cp "$WORK/src/$TESTDISK_TAR" "$WORK/src/$JPEG_TAR" "$PATCH" "$SOURCES/"
# Para que quien descargue el codigo sepa como se compilo el binario.
cp "$0" "$SOURCES/build-photorec.sh"

"$DEST/photorec" /version | head -1
echo "Listo: $DEST"
