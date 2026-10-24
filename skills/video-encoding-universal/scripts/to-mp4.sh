#!/bin/sh
# to-mp4.sh — lleva cualquier vídeo al perfil universal (MP4 H.264/AAC, faststart, avc1).
#
# Uso:
#   to-mp4.sh <entrada> <salida.mp4>
#   to-mp4.sh --force-transcode <entrada> <salida.mp4>
#   to-mp4.sh --force-remux    <entrada> <salida.mp4>
#
# Sin flags decide solo: si el vídeo ya es H.264 hace remux (rápido, sin pérdida);
# si es VP9/AV1/HEVC/MPEG-2/etc. transcodifica con libx264 CRF 22 veryfast.
#
# Variables: FFMPEG, FFPROBE (rutas explícitas), VERBOSE=1.
set -eu

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '· %s\n' "$*" >&2; }

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

MODE=auto
while [ $# -gt 0 ]; do
  case "$1" in
    --force-transcode) MODE=transcode ;;
    --force-remux) MODE=remux ;;
    -h|--help) usage 0 ;;
    --) shift; break ;;
    -*) die "opción desconocida: $1" ;;
    *) break ;;
  esac
  shift
done

[ $# -eq 2 ] || usage 1
IN=$1
OUT=$2
[ -f "$IN" ] || die "no existe el archivo: $IN"
[ "$IN" = "$OUT" ] && die "la salida no puede ser la entrada"

# --- binarios ---------------------------------------------------------------
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FF=$("$SCRIPT_DIR/resolve-ffmpeg.sh") || exit 127
FFPROBE=${FFPROBE:-}
if [ -z "$FFPROBE" ]; then
  guess=$(dirname -- "$FF")/ffprobe
  if [ -x "$guess" ]; then FFPROBE=$guess; else FFPROBE=ffprobe; fi
fi
command -v "$FFPROBE" >/dev/null 2>&1 || [ -x "$FFPROBE" ] || die "ffprobe no encontrado"

probe_stream() {
  # $1 = archivo, $2 = selector (v:0 / a:0), $3 = campo
  "$FFPROBE" -v error -select_streams "$2" -show_entries "stream=$3" -of csv=p=0 "$1" 2>/dev/null | head -n 1
}

vcodec=$(probe_stream "$IN" v:0 codec_name) || true
[ -n "${vcodec:-}" ] || die "el archivo no tiene pista de vídeo"
acodec=$(probe_stream "$IN" a:0 codec_name) || true

if [ "$MODE" = auto ]; then
  if [ "$vcodec" = h264 ]; then MODE=remux; else MODE=transcode; fi
fi

info "entrada: $IN (vídeo=$vcodec, audio=${acodec:-ninguno})"
info "ffmpeg:  $FF"
info "modo:    $MODE"

set -- -y -hide_banner -nostdin -loglevel warning -stats -i "$IN"

if [ "$MODE" = remux ]; then
  set -- "$@" -map 0:v:0 -sn -dn -c:v copy -tag:v avc1
  if [ -n "${acodec:-}" ]; then
    set -- "$@" -map '0:a:0?' -c:a aac -b:a 192k -ac 2
  else
    set -- "$@" -an
  fi
else
  set -- "$@" -map 0:v:0 -sn -dn \
    -c:v libx264 -preset veryfast -crf 22 -profile:v high \
    -pix_fmt yuv420p -vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2' -tag:v avc1
  if [ -n "${acodec:-}" ]; then
    set -- "$@" -map '0:a:0?' -c:a aac -b:a 192k -ac 2
  else
    set -- "$@" -an
  fi
fi

set -- "$@" -movflags +faststart "$OUT"

info "ejecutando ffmpeg…"
"$FF" "$@" || die "ffmpeg falló (mira el log de arriba)"

[ -s "$OUT" ] || die "no se generó la salida"

bytes=$(wc -c < "$OUT" | tr -d ' ')
info "listo: $OUT (${bytes} bytes)"
info "verifica con: $(dirname -- "$0")/verify-mp4.sh \"$OUT\""
