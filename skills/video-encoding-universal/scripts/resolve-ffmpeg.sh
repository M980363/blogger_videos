#!/bin/sh
# resolve-ffmpeg.sh — imprime la ruta del ffmpeg que usará el resto de scripts.
#
# Orden (el primero que exista gana):
#   1. $FFMPEG (si apunta a un ejecutable)
#   2. ffmpeg7                (SynoCommunity, en PATH)
#   3. /usr/local/bin/ffmpeg7
#   4. /volume1/@appstore/ffmpeg/bin/ffmpeg
#   5. /usr/bin/ffmpeg
#   6. ffmpeg                 (PATH)
#
# Salida: ruta en stdout. Código 127 si no hay ninguno.
set -eu

if [ -n "${FFMPEG:-}" ]; then
  if command -v "$FFMPEG" >/dev/null 2>&1; then
    command -v "$FFMPEG"
    exit 0
  fi
  if [ -x "$FFMPEG" ]; then
    printf '%s\n' "$FFMPEG"
    exit 0
  fi
fi

for candidate in ffmpeg7 /usr/local/bin/ffmpeg7 /volume1/@appstore/ffmpeg/bin/ffmpeg /usr/bin/ffmpeg ffmpeg; do
  if command -v "$candidate" >/dev/null 2>&1; then
    command -v "$candidate"
    exit 0
  fi
  if [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
done

printf '%s\n' "ffmpeg no encontrado (probado: \$FFMPEG, ffmpeg7, /usr/local/bin/ffmpeg7, /volume1/@appstore/ffmpeg/bin/ffmpeg, /usr/bin/ffmpeg, ffmpeg)" >&2
exit 127
