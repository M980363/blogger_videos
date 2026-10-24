---
name: video-encoding-universal
description: Perfil único de codificación de vídeo a MP4 H.264/AAC reproducible en Synology DS124, navegadores y Smart TVs (libx264, CRF 22, preset veryfast, faststart, tag avc1). Incluye remux sin pérdida, transcodificación de fallback y verificación con ffprobe.
whenToUse: Cuando haya que convertir, remuxear, normalizar o validar un vídeo antes de publicarlo en Blogger, servirlo desde el NAS DS124 o archivarlo.
---

# Perfil de codificación universal

Todo vídeo que salga de este flujo es un **MP4 H.264/AAC** que se reproduce sin transcodificar
en Safari/iOS, Chrome/Firefox, Smart TV y el Synology DS124.

## Parámetros del perfil (salida final)

| Parámetro | Valor | Por qué |
| --- | --- | --- |
| Contenedor | `.mp4` | Interoperabilidad universal sin transcodificación en cliente |
| Códec de vídeo | `libx264` (H.264/AVC) | Aceleración por hardware universal |
| Tag FourCC | `-tag:v avc1` | Compatibilidad nativa con Safari, QuickTime e iOS |
| Preset | `veryfast` | 1 núcleo ARM64 en el DS124 |
| Calidad | `-crf 22` | Calidad visual transparente, tamaño contenido |
| Códec de audio | `aac` | Estándar estéreo HTML5 |
| Bitrate de audio | `128–192 kbps` | Diálogos y bandas sonoras con fidelidad |
| Streaming | `-movflags +faststart` | `moov` al inicio: reproducción instantánea en web |

Extras que aplica el script y no son negociables para web:

- `-pix_fmt yuv420p` (si el origen es 10-bit/HDR, se convierte; si no, Safari no arranca).
- Dimensiones pares: `scale=trunc(iw/2)*2:trunc(ih/2)*2` (H.264 no admite impares en 4:2:0).
- `-movflags +faststart` siempre, incluso en el remux.
- Sin subtítulos ni datos (`-sn -dn`): el `<track>` va aparte en la web.
- Audio estéreo (`-ac 2`).

## Regla de oro: remux antes que recodificar

```
¿el vídeo ya es H.264?
├─ sí  → REMUX  (-c:v copy)            segundos, sin pérdida de calidad
└─ no  → TRANSCODE (libx264 crf 22)    VP9, AV1, MPEG-2, HEVC, etc.
```

Recodificar un H.264 solo empeora la calidad y consume CPU. El remux cambia contenedor,
arrastra el vídeo tal cual y reencoda únicamente el audio a AAC.

Comprobar el códec de origen:

```bash
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 input.mkv
```

## Comandos

### Remux (origen H.264)

```bash
ffmpeg -y -i input -map 0:v:0 -map 0:a:0? -sn -dn \
  -c:v copy -tag:v avc1 \
  -c:a aac -b:a 192k -ac 2 \
  -movflags +faststart output.mp4
```

### Transcodificación (origen no H.264)

```bash
ffmpeg -y -i input -map 0:v:0 -map 0:a:0? -sn -dn \
  -c:v libx264 -preset veryfast -crf 22 -profile:v high \
  -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -tag:v avc1 \
  -c:a aac -b:a 192k -ac 2 \
  -movflags +faststart output.mp4
```

Sin pista de audio, añade `-an` y omite los flags `-c:a`.

## Verificación obligatoria

No des por buena una conversión sin pasar `verify-mp4.sh`:

| Comprobación | Valor esperado |
| --- | --- |
| `format_name` | contiene `mp4` |
| `codec_name` (vídeo) | `h264` |
| `codec_tag_string` | `avc1` |
| `pix_fmt` | `yuv420p` |
| audio | `aac`, 1–2 canales |
| `faststart` | offset de `moov` < offset de `mdat` |
| duración | coincide con el origen (±1 s) |

## Errores típicos y qué hacer

- **Safari no reproduce / pantalla negra**: falta `avc1`, `yuv420p` o el `moov` está al final.
  Revisa tag, pix_fmt y `faststart` con `verify-mp4.sh`.
- **Vídeo girado en móvil**: el origen trae matriz de rotación. `ffmpeg` la aplica al
  recodificar; si haces remux, añade `-metadata:s:v:0 rotate=0` solo si el reproductor la ignora.
- **Dimensiones impares** (`1921x1081`): H.264 4:2:0 las rechaza; el filtro `scale` las ajusta.
- **10-bit / HDR**: `-pix_fmt yuv420p` resuelve la compatibilidad, pero el color puede apagarse.
  Si importa el HDR, no uses este perfil: publica el original y usa YouTube, que lo conserva.
- **Audio en Opus/Vorbis**: se recodifica a AAC 192k; no intentes copiarlo a MP4.
- **`moov atom not found`**: descarga incompleta; vuelve a bajar el archivo.

## Scripts

```bash
# Conversión con detección de códec (remux o transcode automático)
scripts/to-mp4.sh entrada.mkv salida.mp4
scripts/to-mp4.sh --force-transcode entrada.mp4 salida.mp4

# Verificación del resultado (código de salida != 0 si algo falla)
scripts/verify-mp4.sh salida.mp4

# Binario ffmpeg que se usará (ffmpeg7 del NAS primero)
scripts/resolve-ffmpeg.sh
```

Orden de búsqueda de `ffmpeg`: `$FFMPEG` → `ffmpeg7` → `/usr/local/bin/ffmpeg7` →
`/volume1/@appstore/ffmpeg/bin/ffmpeg` → `/usr/bin/ffmpeg` → `ffmpeg` del `PATH`.
