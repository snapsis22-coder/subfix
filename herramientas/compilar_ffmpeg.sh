#!/bin/zsh
# Compila un ffmpeg/ffprobe mínimo y estático para meterlo dentro de SubFix.app.
#
#     ./herramientas/compilar_ffmpeg.sh
#
# ¿Por qué no copiar el de Homebrew? Porque arrastra más de treinta dylibs
# (x265, SVT-AV1, VMAF, OpenSSL, libvpx…) que esta app no toca jamás: son ~200 MB
# y obligarían a reescribir rutas con install_name_tool. Aquí se compila sólo lo
# que SubFix usa de verdad — leer contenedores y mover pistas de subtítulo — y
# sale un binario de pocos megas sin ninguna dependencia fuera de /usr/lib.
#
# Efecto secundario útil: sin x264/x265 no entra código GPL, así que lo que se
# empaqueta es LGPL 2.1.
set -e

VERSION="${1:-8.1.2}"
cd "$(dirname "$0")/.."
PROYECTO="$PWD"
DESTINO="$PROYECTO/Resources/bin"
TRABAJO="$(mktemp -d)/ffmpeg"

echo "▸ Descargando ffmpeg $VERSION…"
mkdir -p "$TRABAJO"
curl -fsSL "https://ffmpeg.org/releases/ffmpeg-${VERSION}.tar.xz" | tar xJ -C "$TRABAJO" --strip-components=1

echo "▸ Configurando (sólo subtítulos)…"
cd "$TRABAJO"
./configure \
    --prefix="$TRABAJO/instalado" \
    --disable-everything \
    --disable-autodetect \
    --disable-network \
    --disable-doc \
    --disable-shared \
    --enable-static \
    --enable-small \
    --disable-debug \
    --disable-programs --enable-ffmpeg --enable-ffprobe \
    --enable-demuxer=matroska,mov,avi,mpegts,srt,ass,webvtt,subviewer,mpsub \
    --enable-decoder=subrip,ass,ssa,movtext,webvtt,text \
    --enable-encoder=subrip,srt,ass,ssa,webvtt,movtext \
    --enable-muxer=srt,ass,webvtt \
    --enable-protocol=file \
    > /dev/null

echo "▸ Compilando…"
make -j"$(sysctl -n hw.ncpu)" > /dev/null

echo "▸ Comprobando que no quedaron dependencias externas…"
mkdir -p "$DESTINO"
for programa in ffmpeg ffprobe; do
    externas=$(otool -L "$TRABAJO/$programa" | tail -n +2 | grep -v "/usr/lib\|/System" || true)
    if [[ -n "$externas" ]]; then
        echo "  ✗ $programa todavía depende de algo de fuera:"
        echo "$externas"
        exit 1
    fi
    cp "$TRABAJO/$programa" "$DESTINO/$programa"
    strip -S "$DESTINO/$programa" 2>/dev/null || true
    echo "  ✓ $programa — $(du -h "$DESTINO/$programa" | cut -f1)"
done

# La LGPL pide entregar la licencia junto al binario.
cp "$TRABAJO/COPYING.LGPLv2.1" "$PROYECTO/Resources/FFMPEG-LICENSE.txt"

rm -rf "$(dirname "$TRABAJO")"
echo "✓ Listos en Resources/bin — ahora ./build_app.sh los mete en el bundle"
