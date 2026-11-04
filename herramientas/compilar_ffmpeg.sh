#!/bin/zsh
# Compila un ffmpeg/ffprobe mínimo y estático para meterlo dentro de SubFix.app.
# Además de leer subtítulos, sabe empaquetar un .mkv copiando pistas (sin recodificar).
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
#
# Los decodificadores de AUDIO son para comprobar la sincronía de un subtítulo
# bajado cuando el video no trae ninguna pista de texto con que compararlo: se
# saca el audio a 8 kHz mono y se busca dónde hablan (`Sincronia.swift`).
#
# ⚠️ Los decodificadores de VIDEO no son para decodificar: sin ellos ffmpeg no puede
# averiguar cuántos fotogramas B hay que reordenar (`has_b_frames`), supone cero y, al
# copiar un MKV, reescribe las marcas de tiempo mal («Non-monotonic DTS … changing to»).
# El archivo sale con los mismos datos pero el video a tirones. Sólo se usan para
# sondear el principio del archivo; la copia sigue siendo sin recodificar.
set -e

VERSION="${1:-8.1.2}"
cd "$(dirname "$0")/.."
PROYECTO="$PWD"
DESTINO="$PROYECTO/Resources/bin"
TRABAJO="$(mktemp -d)/ffmpeg"

echo "▸ Descargando ffmpeg $VERSION…"
mkdir -p "$TRABAJO"
curl -fsSL "https://ffmpeg.org/releases/ffmpeg-${VERSION}.tar.xz" | tar xJ -C "$TRABAJO" --strip-components=1

echo "▸ Configurando (subtítulos + remux a MKV + audio para comprobar la sincronía)…"
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
    --enable-decoder=h264,hevc,mpeg2video,mpeg4,vp8,vp9,vc1 \
    --enable-encoder=subrip,srt,ass,ssa,webvtt,movtext \
    --enable-muxer=srt,ass,webvtt,matroska \
    --enable-decoder=aac,aac_latm,ac3,eac3,dca,truehd,mlp,opus,vorbis,flac,mp3,mp2,alac \
    --enable-decoder=pcm_s16le,pcm_s24le,pcm_s16be,pcm_bluray,pcm_dvd \
    --enable-encoder=pcm_s16le --enable-muxer=pcm_s16le \
    --enable-filter=aresample,aformat,anull,pan,highpass,lowpass \
    --enable-swresample \
    --enable-parsers --enable-bsfs \
    --enable-protocol=file,pipe \
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
