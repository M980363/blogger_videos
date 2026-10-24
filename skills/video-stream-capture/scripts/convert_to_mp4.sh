#!/bin/sh
# convert_to_mp4.sh — convierte un archivo (MKV, WebM, TS, MOV…) a MP4 del perfil universal.
#
# Uso:
#   convert_to_mp4.sh <entrada> <salida.mp4>
#
# Lógica:
#   Paso 1  remux ultra-rápido  -> ffmpeg -c:v copy -c:a aac -movflags +faststart
#   Paso 2  fallback            -> libx264 veryfast CRF 22 + aac 192k + faststart
#
# El paso se elige comprobando el códec real del vídeo con ffprobe: VP9/AV1/HEVC/MPEG-2
# no se pueden copiar a MP4 con compatibilidad universal, así que se transcodifican.
set -eu

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '· %s\n' "$*" >&2; }
usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

[ $# -eq 2 ] || usage 1
IN=$1
OUT=$2
[ -f "$IN" ] || die "no existe: $IN"
[ "$IN" = "$OUT" ] && die "la salida no puede ser la entrada"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FF_SH="$SCRIPT_DIR/../../video-encoding-universal/scripts/resolve-ffmpeg.sh"
if [ -x "$FF_SH" ]; then
  FF=$("$FF_SH") || exit 127
else
  FF=${FFMPEG:-ffmpeg}
fi

FFPROBE=${FFPROBE:-}
if [ -z "$FFPROBE" ]; then
  guess=$(dirname -- "$FF")/ffprobe
  if [ -x "$guess" ]; then FFPROBE=$guess; else FFPROBE=ffprobe; fi
fi
command -v "$FFPROBE" >/dev/null 2>&1 || [ -x "$FFPROBE" ] || die "ffprobe no encontrado"

field() { "$FFPROBE" -v error -select_streams "$1" -show_entries "stream=$2" -of csv=p=0 "$IN" 2>/dev/null | head -n 1; }

VCODEC=$(field v:0 codec_name) || true
[ -n "${VCODEC:-}" ] || die "el archivo no tiene pista de vídeo"
ACODEC=$(field a:0 codec_name) || true
info "origen: vídeo=$VCODEC audio=${ACODEC:-ninguno}"

# --- Paso 1: remux -----------------------------------------------------------
if [ "$VCODEC" = h264 ]; then
  info "paso 1: remux sin recodificar vídeo"
  set -- -y -hide_banner -nostdin -loglevel warning -i "$IN" -map 0:v:0 -sn -dn \
    -c:v copy -tag:v avc1
  if [ -n "${ACODEC:-}" ]; then
    set -- "$@" -map '0:a:0?' -c:a aac -b:a 192k -ac 2
  else
    set -- "$@" -an
  fi
  set -- "$@" -movflags +faststart "$OUT"
  if "$FF" "$@"; then
    [ -s "$OUT" ] && { info "listo: $OUT"; exit 0; }
  fi
  info "el remux no produjo un archivo válido; se pasa al paso 2"
fi

# --- Paso 2: transcodificación ----------------------------------------------
info "paso 2: transcodificación ($VCODEC → h264)"
set -- -y -hide_banner -nostdin -loglevel warning -i "$IN" -map 0:v:0 -sn -dn \
  -c:v libx264 -preset veryfast -crf 22 -profile:v high \
  -pix_fmt yuv420p -vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2' -tag:v avc1
if [ -n "${ACODEC:-}" ]; then
  set -- "$@" -map '0:a:0?' -c:a aac -b:a 192k -ac 2
else
  set -- "$@" -an
fi
set -- "$@" -movflags +faststart "$OUT"

"$FF" "$@" || die "ffmpeg falló"
[ -s "$OUT" ] || die "no se generó la salida"
info "listo: $OUT"
