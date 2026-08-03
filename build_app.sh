#!/bin/zsh
# Compila SubFix, arma el bundle .app, lo firma e instala en /Applications.
# Molde tomado de ~/Documents/Proyectos/Boveda/build_app.sh.
set -e

cd "$(dirname "$0")"
PROYECTO="$PWD"
NOMBRE_APP="SubFix"
PRODUCTO="SubFix"
DESTINO="/Applications/${NOMBRE_APP}.app"
IDENTIDAD="snapsis-dev"

echo "▸ Compilando…"
swift build -c release --product "$PRODUCTO"

echo "▸ Armando el bundle…"
BUNDLE="$PROYECTO/.build/${NOMBRE_APP}.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$PROYECTO/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$PROYECTO/.build/release/$PRODUCTO" "$BUNDLE/Contents/MacOS/$NOMBRE_APP"
[ -f "$PROYECTO/Resources/AppIcon.icns" ] && cp "$PROYECTO/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/"

# ffmpeg y ffprobe propios (ver herramientas/compilar_ffmpeg.sh). Sin esto la app
# depende de que la Mac tenga Homebrew.
if [ -d "$PROYECTO/Resources/bin" ]; then
    cp -R "$PROYECTO/Resources/bin" "$BUNDLE/Contents/Resources/bin"
    cp "$PROYECTO/Resources/FFMPEG-LICENSE.txt" "$BUNDLE/Contents/Resources/" 2>/dev/null || true
    echo "  ffmpeg propio incluido ($(du -sh "$PROYECTO/Resources/bin" | cut -f1))"
else
    echo "  ⚠ Sin Resources/bin: la app usará el ffmpeg de Homebrew si lo hay."
fi

# Con firma estable (no ad-hoc) los permisos de TCC sobreviven al rebuild.
#
# ⚠ `security find-identity` NO sirve para decidir esto: si al certificado le falta
# el ajuste de confianza responde «0 valid identities» aunque `codesign` sí sepa
# firmar con él. La única prueba fiable es intentar una firma de verdad.
SONDA="$(mktemp -d)"
cp /bin/echo "$SONDA/sonda"
if codesign --force --sign "$IDENTIDAD" "$SONDA/sonda" >/dev/null 2>&1; then
    SIGN="$IDENTIDAD"
    echo "  firmando con '$IDENTIDAD' — los permisos sobreviven al rebuild"
else
    SIGN="-"
    echo "  ⚠ No pude firmar con '$IDENTIDAD' — firma ad-hoc, se pierden los permisos ya concedidos."
fi
rm -rf "$SONDA"

# xattr -cr es obligatorio antes de firmar, o codesign falla con
# "resource fork, Finder information, or similar detritus not allowed".
# Y hay que firmar el bundle YA INSTALADO: en ~/Documents con iCloud activo, el
# proveedor de archivos vuelve a ensuciar la carpeta y la firma nace rota.
# Los binarios que van dentro se firman ANTES que el bundle: si se firman
# después, la firma del bundle deja de cuadrar y macOS se niega a abrir la app.
firmar() {
    xattr -cr "$1"
    for interno in "$1"/Contents/Resources/bin/*; do
        [ -f "$interno" ] && codesign --force --sign "$SIGN" "$interno"
    done
    codesign --force --sign "$SIGN" "$1"
    codesign --verify --deep --strict "$1"
}

if [[ "$1" == "--sin-instalar" ]]; then
    echo "▸ Firmando en el sitio…"
    firmar "$BUNDLE" || echo "  ⚠ La firma no verifica (¿iCloud reensuciando .build?)"
    echo "✓ Bundle listo (sin instalar): $BUNDLE"
    exit 0
fi

echo "▸ Instalando en $DESTINO…"
rm -rf "$DESTINO"
cp -R "$BUNDLE" "$DESTINO"

echo "▸ Firmando lo instalado…"
firmar "$DESTINO"

echo "✓ Listo: $DESTINO"
