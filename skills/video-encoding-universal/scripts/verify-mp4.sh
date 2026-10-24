#!/bin/sh
# verify-mp4.sh — valida que un MP4 cumple el perfil universal.
#
# Uso:
#   verify-mp4.sh <archivo.mp4> [origen]
#
# Comprueba: contenedor MP4, vídeo H.264, tag avc1, yuv420p, audio AAC estéreo,
# faststart (moov antes de mdat) y, si se pasa el origen, duración equivalente.
#
# Código de salida: 0 todo correcto, 1 algún fallo, 2 uso incorrecto.
set -u

if [ $# -lt 1 ]; then
  printf 'uso: %s <archivo.mp4> [origen]\n' "$0" >&2
  exit 2
fi

FILE=$1
SRC=${2:-}
[ -f "$FILE" ] || { printf 'error: no existe %s\n' "$FILE" >&2; exit 2; }

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FF=$("$SCRIPT_DIR/resolve-ffmpeg.sh" 2>/dev/null) || FF=ffmpeg
FFPROBE=${FFPROBE:-}
if [ -z "$FFPROBE" ]; then
  guess=$(dirname -- "$FF")/ffprobe
  if [ -x "$guess" ]; then FFPROBE=$guess; else FFPROBE=ffprobe; fi
fi
command -v "$FFPROBE" >/dev/null 2>&1 || [ -x "$FFPROBE" ] || {
  printf 'error: ffprobe no encontrado\n' >&2
  exit 2
}

OK=0
FAIL=0

row() {
  # $1 = 1 ok / 0 fallo, $2 = nombre, $3 = valor
  if [ "$1" = 1 ]; then
    printf '  [ ok ]  %-16s %s\n' "$2" "$3"
    OK=$((OK + 1))
  else
    printf '  [FAIL]  %-16s %s\n' "$2" "$3"
    FAIL=$((FAIL + 1))
  fi
}

field() {
  # $1 selector, $2 campo
  "$FFPROBE" -v error -select_streams "$1" -show_entries "stream=$2" -of csv=p=0 "$FILE" 2>/dev/null | head -n 1
}

printf '\nVerificando %s\n' "$FILE"

fmt=$("$FFPROBE" -v error -show_entries format=format_name -of csv=p=0 "$FILE" 2>/dev/null | head -n 1)
case "$fmt" in
  *mp4*) row 1 formato "$fmt" ;;
  *)     row 0 formato "${fmt:-desconocido}" ;;
esac

vcodec=$(field v:0 codec_name)
[ "$vcodec" = h264 ] && row 1 video "$vcodec" || row 0 video "${vcodec:-ninguno}"

tag=$(field v:0 codec_tag_string)
[ "$tag" = avc1 ] && row 1 tag "$tag" || row 0 tag "${tag:-ninguno}"

pix=$(field v:0 pix_fmt)
[ "$pix" = yuv420p ] && row 1 pix_fmt "$pix" || row 0 pix_fmt "${pix:-ninguno}"

acodec=$(field a:0 codec_name)
if [ -z "$acodec" ]; then
  printf '  [ ok ]  %-16s %s\n' audio "sin pista de audio"
  OK=$((OK + 1))
else
  [ "$acodec" = aac ] && row 1 audio "$acodec" || row 0 audio "$acodec"
  ch=$(field a:0 channels)
  case "${ch:-0}" in
    1|2) row 1 canales "${ch} (estéreo/mono)" ;;
    *)   row 0 canales "${ch:-?} (>2; el perfil pide -ac 2)" ;;
  esac
fi

# --- faststart: moov debe aparecer antes que mdat ---------------------------
moov=""
mdat=""
if head -c 8388608 "$FILE" 2>/dev/null | grep -abo -m1 moov >/dev/null 2>&1; then
  moov=$(head -c 8388608 "$FILE" | grep -abo -m1 moov | head -n 1 | cut -d: -f1)
  mdat=$(head -c 8388608 "$FILE" | grep -abo -m1 mdat | head -n 1 | cut -d: -f1)
fi

if [ -n "$moov" ] && [ -n "$mdat" ]; then
  if [ "$moov" -lt "$mdat" ]; then
    row 1 faststart "moov@$moov < mdat@$mdat"
  else
    row 0 faststart "moov@$moov > mdat@$mdat (reproduce tarde en web)"
  fi
else
  printf '  [ -- ]  %-16s %s\n' faststart "no comprobable (falta grep GNU o cabeceras fuera de los primeros 8 MiB)"
fi

# --- duración ---------------------------------------------------------------
dur=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$FILE" 2>/dev/null | head -n 1)
if [ -n "${SRC:-}" ] && [ -f "$SRC" ]; then
  sdur=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$SRC" 2>/dev/null | head -n 1)
  if [ -n "$dur" ] && [ -n "$sdur" ]; then
    result=$(awk -v a="$dur" -v b="$sdur" 'BEGIN { d = a - b; if (d < 0) d = -d; print (d <= 1.0) ? 1 : 0 }')
    if [ "$result" = 1 ]; then
      row 1 duracion "$(printf '%.1f' "$dur")s vs $(printf '%.1f' "$sdur")s origen"
    else
      row 0 duracion "$(printf '%.1f' "$dur")s vs $(printf '%.1f' "$sdur")s origen"
    fi
  fi
elif [ -n "$dur" ]; then
  printf '  [ -- ]  %-16s %s\n' duracion "$(printf '%.1f' "$dur")s (sin origen para comparar)"
fi

printf '\n%d comprobaciones OK, %d fallidas\n\n' "$OK" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
