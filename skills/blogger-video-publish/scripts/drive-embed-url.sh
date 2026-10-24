#!/bin/sh
# drive-embed-url.sh — convierte un enlace de Google Drive en URL de incrustación.
#
# Uso:
#   drive-embed-url.sh <url-o-id>            imprime la URL /preview
#   drive-embed-url.sh <url-o-id> --html     imprime el bloque HTML responsive
#   drive-embed-url.sh <url-o-id> --ratio 9:16 --html
#
# Acepta /file/d/ID/view, open?id=ID, uc?id=ID o el ID suelto.
set -eu

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

[ $# -ge 1 ] || usage 1
INPUT=$1
shift

HTML=0
RATIO=16:9
TITLE="Vídeo"
while [ $# -gt 0 ]; do
  case "$1" in
    --html) HTML=1; shift ;;
    --ratio) [ $# -ge 2 ] || die "falta valor para --ratio"; RATIO=$2; shift 2 ;;
    --title) [ $# -ge 2 ] || die "falta valor para --title"; TITLE=$2; shift 2 ;;
    -h|--help) usage 0 ;;
    *) die "opción desconocida: $1" ;;
  esac
done

ID=""
ID=$(printf '%s' "$INPUT" | sed -n 's#.*/d/\([A-Za-z0-9_-]\{20,\}\).*#\1#p' | head -n 1)
if [ -z "$ID" ]; then
  ID=$(printf '%s' "$INPUT" | sed -n 's#.*[?&]id=\([A-Za-z0-9_-]\{20,\}\).*#\1#p' | head -n 1)
fi
if [ -z "$ID" ]; then
  case "$INPUT" in
    [A-Za-z0-9_-][A-Za-z0-9_-]*) ID=$INPUT ;;
  esac
fi
[ -n "$ID" ] || die "no se pudo extraer el ID de Drive de: $INPUT"

case "$RATIO" in
  16:9) PAD=56.25 ;;
  9:16) PAD=177.78 ;;
  4:3)  PAD=75 ;;
  1:1)  PAD=100 ;;
  *) die "proporción no soportada: $RATIO (usa 16:9, 9:16, 4:3 o 1:1)" ;;
esac

URL="https://drive.google.com/file/d/$ID/preview"

if [ "$HTML" = 1 ]; then
  cat <<EOF
<div style="position:relative;width:100%;max-width:800px;margin:0 auto;padding-bottom:${PAD}%;height:0;overflow:hidden;">
  <iframe src="$URL"
          title="$TITLE"
          style="position:absolute;top:0;left:0;width:100%;height:100%;border:0;"
          allow="autoplay; fullscreen; picture-in-picture"
          allowfullscreen="allowfullscreen"
          loading="lazy"></iframe>
</div>
EOF
else
  printf '%s\n' "$URL"
fi
