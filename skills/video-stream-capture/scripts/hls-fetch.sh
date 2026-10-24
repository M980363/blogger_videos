#!/bin/sh
# hls-fetch.sh — descarga un flujo HLS y lo deja en MP4 H.264/AAC con faststart.
#
# Uso:
#   hls-fetch.sh <url-m3u8> <salida.mp4> [opciones]
#
# Opciones:
#   --referer <url>   cabecera Referer (la que use el navegador)
#   --cookie <str>    cabecera Cookie completa
#   --ua <str>        User-Agent (por defecto uno de Chrome de escritorio)
#   --direct          deja que ffmpeg resuelva el manifiesto (AES-128, byte-range)
#
# El master playlist se resuelve a la variante de mayor BANDWIDTH. Los segmentos se
# descargan en orden y se ensamblan con el demuxer concat; si el remux falla se
# reintenta transcodificando al perfil universal.
set -eu

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '· %s\n' "$*" >&2; }
usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

[ $# -ge 2 ] || usage 1
URL=$1
OUT=$2
shift 2

MODE=segments
REFERER=""
COOKIE=""
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

while [ $# -gt 0 ]; do
  case "$1" in
    --referer) [ $# -ge 2 ] || die "falta valor para --referer"; REFERER=$2; shift 2 ;;
    --cookie)  [ $# -ge 2 ] || die "falta valor para --cookie";  COOKIE=$2;  shift 2 ;;
    --ua)      [ $# -ge 2 ] || die "falta valor para --ua";      UA=$2;      shift 2 ;;
    --direct)  MODE=direct; shift ;;
    -h|--help) usage 0 ;;
    *) die "opción desconocida: $1" ;;
  esac
done

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FF_SH="$SCRIPT_DIR/../../video-encoding-universal/scripts/resolve-ffmpeg.sh"
if [ -x "$FF_SH" ]; then
  FF=$("$FF_SH") || exit 127
else
  FF=${FFMPEG:-ffmpeg}
fi

curl_fetch() {
  # $1 = url, $2 = destino
  if [ -n "$REFERER" ] && [ -n "$COOKIE" ]; then
    curl -fsSL --retry 3 --retry-delay 2 -A "$UA" -e "$REFERER" -H "Cookie: $COOKIE" -o "$2" "$1"
  elif [ -n "$REFERER" ]; then
    curl -fsSL --retry 3 --retry-delay 2 -A "$UA" -e "$REFERER" -o "$2" "$1"
  elif [ -n "$COOKIE" ]; then
    curl -fsSL --retry 3 --retry-delay 2 -A "$UA" -H "Cookie: $COOKIE" -o "$2" "$1"
  else
    curl -fsSL --retry 3 --retry-delay 2 -A "$UA" -o "$2" "$1"
  fi
}

origin_of() { printf '%s' "$1" | sed -n 's#^\(https\{0,1\}://[^/]*\).*#\1#p'; }
base_of()   { printf '%s' "$1" | sed 's#[^/]*$##'; }
resolve_url() {
  case "$1" in
    http://*|https://*) printf '%s' "$1" ;;
    /*) printf '%s%s' "$(origin_of "$2")" "$1" ;;
    *)  printf '%s%s' "$(base_of "$2")" "$1" ;;
  esac
}

# ffmpeg nativo (Windows) no entiende rutas MSYS (/tmp/...): el concat.txt necesita
# rutas nativas con barras normales.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

if [ "$MODE" = direct ]; then
  info "modo directo: ffmpeg resuelve el manifiesto"
  HEADERS=""
  if [ -n "$REFERER" ]; then
    HEADERS=$(printf 'Referer: %s\r\n' "$REFERER")
  fi
  if [ -n "$COOKIE" ]; then
    HEADERS="$HEADERS$(printf 'Cookie: %s\r\n' "$COOKIE")"
  fi
  if [ -n "$HEADERS" ]; then
    "$FF" -y -hide_banner -loglevel warning -headers "$HEADERS" -user_agent "$UA" \
      -i "$URL" -c copy -movflags +faststart "$OUT"
  else
    "$FF" -y -hide_banner -loglevel warning -user_agent "$UA" \
      -i "$URL" -c copy -movflags +faststart "$OUT"
  fi
  [ -s "$OUT" ] || die "ffmpeg no generó salida"
  info "listo: $OUT"
  exit 0
fi

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t hlscap)
trap 'rm -rf "$TMP"' EXIT INT TERM

info "descargando manifiesto"
curl_fetch "$URL" "$TMP/playlist.m3u8" || die "no se pudo descargar el manifiesto (¿Referer/Cookie?)"
[ -s "$TMP/playlist.m3u8" ] || die "manifiesto vacío"
grep -q '^#EXTM3U' "$TMP/playlist.m3u8" || die "el contenido no es un manifiesto HLS"

if grep -q '^#EXT-X-STREAM-INF' "$TMP/playlist.m3u8"; then
  VARIANT=$(awk '
    /^#EXT-X-STREAM-INF:/ {
      line = $0
      sub(/^#EXT-X-STREAM-INF:/, "", line)
      n = split(line, attrs, ",")
      bw = 0
      for (i = 1; i <= n; i++) {
        split(attrs[i], kv, "=")
        if (kv[1] == "BANDWIDTH") bw = kv[2] + 0
      }
      getline
      while ($0 ~ /^#/ || $0 == "") getline
      if (bw > best) { best = bw; uri = $0 }
    }
    END { if (uri != "") print uri }
  ' "$TMP/playlist.m3u8")

  [ -n "$VARIANT" ] || die "no se pudo elegir variante del master playlist"
  MEDIA_URL=$(resolve_url "$VARIANT" "$URL")
  info "variante elegida: $MEDIA_URL"
  curl_fetch "$MEDIA_URL" "$TMP/media.m3u8" || die "no se pudo descargar la variante"
else
  MEDIA_URL=$URL
  cp "$TMP/playlist.m3u8" "$TMP/media.m3u8"
fi

grep -q '^#EXT-X-ENDLIST' "$TMP/media.m3u8" || info "aviso: el manifiesto no termina en #EXT-X-ENDLIST (stream en vivo)"

awk '
  /^#EXT-X-MAP:/ {
    if (match($0, /URI="[^"]+"/)) {
      uri = substr($0, RSTART + 5, RLENGTH - 6)
      print "MAP " uri
    }
    next
  }
  /^#/ { next }
  NF { print "SEG " $0 }
' "$TMP/media.m3u8" > "$TMP/list.txt"

[ -s "$TMP/list.txt" ] || die "el manifiesto no contiene segmentos"

: > "$TMP/concat.txt"
COUNT=0
INIT=0
while IFS=' ' read -r KIND URI; do
  [ -n "${URI:-}" ] || continue
  FULL=$(resolve_url "$URI" "$MEDIA_URL")
  if [ "$KIND" = MAP ]; then
    NAME=init.mp4
    INIT=1
  else
    COUNT=$((COUNT + 1))
    NAME=$(printf 'seg_%05d.ts' "$COUNT")
  fi
  info "descargando $NAME"
  curl_fetch "$FULL" "$TMP/$NAME" || die "fallo al descargar $FULL"
  # shellcheck disable=SC2016
  printf "file '%s'\n" "$(native_path "$TMP/$NAME")" >> "$TMP/concat.txt"
done < "$TMP/list.txt"

[ "$COUNT" -gt 0 ] || die "no se descargó ningún segmento"

if [ "$INIT" = 1 ]; then
  # HLS fMP4 (CMAF): init + fragmentos se ensamblan concatenando bytes.
  info "fMP4 detectado: concatenando init + $COUNT fragmentos"
  cat "$TMP/init.mp4" "$TMP"/seg_*.ts > "$TMP/raw.mp4" || die "no se pudo concatenar"
  if "$FF" -y -hide_banner -loglevel warning -i "$TMP/raw.mp4" \
    -c copy -movflags +faststart "$OUT" 2>"$TMP/ff-remux.log"; then
    [ -s "$OUT" ] || die "no se generó la salida"
    info "listo: $OUT ($COUNT segmentos, remux sin pérdida)"
    exit 0
  fi
  info "remux fMP4 fallido; transcodificando al perfil universal"
  "$FF" -y -hide_banner -loglevel warning -i "$TMP/raw.mp4" \
    -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p -tag:v avc1 \
    -c:a aac -b:a 192k -ac 2 -movflags +faststart "$OUT" 2>"$TMP/ff-xcode.log" \
    || { cat "$TMP/ff-remux.log" "$TMP/ff-xcode.log" >&2; die "ffmpeg falló con este flujo; prueba --direct"; }
  info "listo: $OUT ($COUNT segmentos, transcodificado)"
  exit 0
fi

info "ensamblando $COUNT segmentos con el demuxer concat"

if ! "$FF" -y -hide_banner -loglevel warning -f concat -safe 0 -i "$TMP/concat.txt" \
  -c copy -movflags +faststart "$OUT" 2>"$TMP/ff-remux.log"; then
  info "remux no válido para estos segmentos; transcodificando al perfil universal"
  "$FF" -y -hide_banner -loglevel warning -f concat -safe 0 -i "$TMP/concat.txt" \
    -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p -tag:v avc1 \
    -c:a aac -b:a 192k -ac 2 -movflags +faststart "$OUT" 2>"$TMP/ff-xcode.log" \
    || { cat "$TMP/ff-remux.log" "$TMP/ff-xcode.log" >&2; die "ffmpeg falló con este flujo; prueba --direct"; }
fi

[ -s "$OUT" ] || die "no se generó la salida"
info "listo: $OUT ($COUNT segmentos)"
