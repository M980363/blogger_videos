#!/bin/sh
# smoke.sh — prueba de humo del perfil universal y de convert_to_mp4.sh.
#
# Genera vídeos sintéticos con ffmpeg (sin dependencias de red) y comprueba:
#   1. MKV mpeg4 + PCM  -> convert_to_mp4.sh transcodifica y verify-mp4.sh pasa
#   2. MP4 H.264        -> to-mp4.sh remuxea (sin recodificar vídeo) y verify pasa
#
# Uso: FFMPEG=/ruta/ffmpeg bash tests/smoke.sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
ENC="$ROOT/skills/video-encoding-universal/scripts"
CAP="$ROOT/skills/video-stream-capture/scripts"

FF=${FFMPEG:-ffmpeg}
command -v "$FF" >/dev/null 2>&1 || [ -x "$FF" ] || { echo "ffmpeg no encontrado (define FFMPEG)" >&2; exit 127; }

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t smoke)
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "· generando origen mpeg4/pcm (mkv)"
"$FF" -y -hide_banner -loglevel error \
  -f lavfi -i testsrc2=size=640x360:rate=25 \
  -f lavfi -i sine=frequency=440:sample_rate=48000 \
  -t 2 -c:v mpeg4 -c:a pcm_s16le "$TMP/src.mkv"

echo "· convert_to_mp4.sh"
"$CAP/convert_to_mp4.sh" "$TMP/src.mkv" "$TMP/out1.mp4"

echo "· verify-mp4.sh (transcodificado)"
"$ENC/verify-mp4.sh" "$TMP/out1.mp4" "$TMP/src.mkv"

echo "· generando origen H.264 (mkv)"
"$FF" -y -hide_banner -loglevel error \
  -f lavfi -i testsrc2=size=640x360:rate=25 \
  -f lavfi -i sine=frequency=660:sample_rate=48000 \
  -t 2 -c:v libx264 -preset ultrafast -c:a aac "$TMP/src264.mkv"

echo "· to-mp4.sh (debe remuxear)"
"$ENC/to-mp4.sh" "$TMP/src264.mkv" "$TMP/out2.mp4"

echo "· verify-mp4.sh (remux)"
"$ENC/verify-mp4.sh" "$TMP/out2.mp4" "$TMP/src264.mkv"

echo
echo "OK: perfil universal verificado en los dos caminos (transcode y remux)"
