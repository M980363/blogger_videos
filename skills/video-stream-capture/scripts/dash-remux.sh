#!/bin/sh
# dash-remux.sh — ensambla fragmentos DASH/fMP4 (.m4s) en un MP4 reproducible.
#
# Uso:
#   dash-remux.sh <salida.mp4> <init.mp4> <seg1.m4s> [seg2.m4s ...]
#   dash-remux.sh <salida.mp4> --mpd <url.mpd> [--referer URL] [--cookie STR]
#
# Modo fragmentos (CMAF): los fragmentos son `moof`+`mdat` consecutivos, así que el
# ensamblado correcto es concatenar BYTES (init + fragmentos) y luego remuxear a MP4
# con la cabecera al principio:
#
#   cat init.mp4 seg1.m4s seg2.m4s ... > raw.mp4
#   ffmpeg -y -i raw.mp4 -c copy -movflags +faststart salida.mp4
#
# El demuxer `concat` de ffmpeg NO sirve para fMP4: produce un archivo de unos cientos
# de bytes porque no interpreta el `moof` inicial de cada fragmento. Se mantiene como
# fallback para fragmentos MPEG-TS.
set -eu

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '· %s\n' "$*" >&2; }
usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

[ $# -ge 2 ] || usage 1
OUT=$1
shift

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

if [ "$1" = "--mpd" ]; then
  [ $# -ge 2 ] || die "falta la URL del .mpd"
  MPD=$2
  shift 2
  REFERER=""
  COOKIE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --referer) REFERER=$2; shift 2 ;;
      --cookie)  COOKIE=$2;  shift 2 ;;
      *) die "opción desconocida: $1" ;;
    esac
  done

  HEADERS=""
  if [ -n "$REFERER" ]; then HEADERS=$(printf 'Referer: %s\r\n' "$REFERER"); fi
  if [ -n "$COOKIE" ]; then HEADERS="$HEADERS$(printf 'Cookie: %s\r\n' "$COOKIE")"; fi

  info "resolviendo el manifiesto DASH con ffmpeg"
  if [ -n "$HEADERS" ]; then
    "$FF" -y -hide_banner -loglevel warning -headers "$HEADERS" -i "$MPD" \
      -c copy -movflags +faststart "$OUT"
  else
    "$FF" -y -hide_banner -loglevel warning -i "$MPD" \
      -c copy -movflags +faststart "$OUT"
  fi
  [ -s "$OUT" ] || die "ffmpeg no generó salida"
  info "listo: $OUT"
  exit 0
fi

[ $# -ge 2 ] || die "faltan fragmentos: init.mp4 + al menos un .m4s"
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t dashremux)
trap 'rm -rf "$TMP"' EXIT INT TERM

FIRST=1
: > "$TMP/list.txt"
for f in "$@"; do
  [ -f "$f" ] || die "no existe: $f"
  if [ "$FIRST" = 1 ]; then
    info "init segment: $f"
    FIRST=0
  fi
  printf '%s\n' "$f" >> "$TMP/list.txt"
done

COUNT=$(wc -l < "$TMP/list.txt" | tr -d ' ')
info "concatenando $COUNT archivos (bytes)"

: > "$TMP/raw.mp4"
while IFS= read -r f; do
  cat "$f" >> "$TMP/raw.mp4" || die "no se pudo leer $f"
done < "$TMP/list.txt"

DUR=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$TMP/raw.mp4" 2>/dev/null | head -n 1)
VSTREAMS=$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$TMP/raw.mp4" 2>/dev/null | head -n 1)

if [ -z "${VSTREAMS:-}" ] || [ -z "${DUR:-}" ] || [ "${DUR%%.*}" = "0" ]; then
  info "la concatenación directa no produjo un flujo válido; probando el demuxer concat"
  : > "$TMP/concat.txt"
  while IFS= read -r f; do
    ABS=$(CDPATH= cd -- "$(dirname -- "$f")" && pwd)/$(basename -- "$f")
    if command -v cygpath >/dev/null 2>&1; then ABS=$(cygpath -m "$ABS"); fi
    # shellcheck disable=SC2016
    printf "file '%s'\n" "$ABS" >> "$TMP/concat.txt"
  done < "$TMP/list.txt"
  "$FF" -y -hide_banner -loglevel warning -f concat -safe 0 -i "$TMP/concat.txt" \
    -c copy -movflags +faststart "$OUT" \
    || die "este conjunto de fragmentos no se puede ensamblar; usa --mpd <url>"
else
  info "remuxeando a MP4 ($VSTREAMS, ${DUR}s)"
  "$FF" -y -hide_banner -loglevel warning -i "$TMP/raw.mp4" \
    -c copy -movflags +faststart "$OUT" \
    || die "el remux falló; usa --mpd <url>"
fi

[ -s "$OUT" ] || die "no se generó la salida"
BYTES=$(wc -c < "$OUT" | tr -d ' ')
info "listo: $OUT ($BYTES bytes, sin pérdida)"
