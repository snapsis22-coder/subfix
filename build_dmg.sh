#!/bin/bash
# Genera SubFix-<versión>.dmg con fondo, layout de iconos y enlace a /Applications.
# Mismo molde que los DMG de Calculadora+, TRM Fixer y Peek a Boo. Uso: ./build_dmg.sh
#
# ⚠ Correr SIEMPRE este script, nunca un `hdiutil create` pelado: eso pierde el fondo,
# las posiciones de los iconos y el LÉEME.
#
# Sin .zip a propósito: el DMG ya va comprimido (UDZO) y el zip sólo duplica archivos.
set -e

APP="/Applications/SubFix.app"
VOL="SubFix"
BG="$(dirname "$0")/dmg_assets/background.png"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
OUT="${1:-$HOME/Desktop/SubFix-$VERSION.dmg}"
TMP_DMG="/tmp/SubFix-rw.dmg"
MNT="/Volumes/$VOL"
echo "==> Versión: $VERSION"

echo "==> Limpieza previa"
hdiutil detach "$MNT" >/dev/null 2>&1 || true
rm -f "$TMP_DMG" "$OUT"

# 20m: la app pesa menos de 4 MB con su ffmpeg incluido.
echo "==> Creando DMG temporal de lectura/escritura"
hdiutil create -volname "$VOL" -srcfolder "$APP" -fs HFS+ -format UDRW -size 20m "$TMP_DMG"

echo "==> Montando"
hdiutil attach "$TMP_DMG" -mountpoint "$MNT"

echo "==> Enlace a /Applications, fondo y LÉEME"
ln -s /Applications "$MNT/Applications"
mkdir -p "$MNT/.background"
cp "$BG" "$MNT/.background/background.png"
cat > "$MNT/LÉEME.txt" <<'TXT'
SubFix — Made by snapsis

Arrastra la app sobre "Applications".

PRIMERA VEZ QUE LA ABRAS
  1. Doble clic. macOS dirá que no se puede abrir. Cierra el aviso.
  2. Ve a  Ajustes del Sistema > Privacidad y Seguridad
     y baja hasta el mensaje sobre "SubFix".
  3. Pulsa "Abrir de todos modos" y confirma.
  A partir de ahí abre con doble clic como cualquier app.

  (El truco viejo de clic derecho > Abrir YA NO funciona: Apple lo quitó
   en macOS 15.)

  Atajo si prefieres la Terminal, hace lo mismo de una vez:
     xattr -cr "/Applications/SubFix.app"

QUÉ HACE
  • Deja el subtítulo en español junto a la película, con el formato que
    los televisores de 2019 sí reproducen: mismo nombre que el vídeo,
    UTF-8 con BOM y saltos CRLF.
  • Lo saca de la pista incrustada, de un .srt suelto de la carpeta o de
    OpenSubtitles, en ese orden.
  • Repara los .srt que vienen mal codificados (los de las tildes rotas).
  • Puede vigilar tu carpeta de descargas y hacerlo solo.

QUÉ NO HACE
  • Subtítulos de imagen (PGS de Blu-ray, VobSub de DVD): eso necesita OCR.
    Cuando los encuentra lo dice, no falla en silencio.

NO NECESITA NADA MÁS
  Lleva su propio ffmpeg dentro. No hace falta instalar Homebrew.

REQUISITOS
  Mac con Apple Silicon (M1/M2/M3/M4) y macOS 14 o superior.
TXT

echo "==> Configurando vista del Finder (mismo layout que las otras apps)"
osascript <<EOF
tell application "Finder"
    tell disk "$VOL"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 108
        set text size of theViewOptions to 12
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "SubFix.app" of container window to {165, 245}
        set position of item "Applications" of container window to {495, 245}
        set position of item "LÉEME.txt" of container window to {330, 400}
        set the bounds of container window to {200, 100, 860, 663}
        update without registering applications
        delay 1
        set the bounds of container window to {200, 100, 860, 663}
        update without registering applications
        delay 2
        close
        open
        delay 2
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

echo "==> Desmontando"
sync
sleep 2
hdiutil detach "$MNT"

echo "==> Comprimiendo a UDZO"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -f "$TMP_DMG"

echo "==> Listo:"
ls -lh "$OUT"
