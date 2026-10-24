---
name: video-stream-capture
description: Descarga y ensambla vídeo de flujos HLS (.m3u8/.ts), DASH/fMP4 (.mpd/.m4s) y archivos directos (MKV, WebM, MPEG-TS) dejándolos en MP4 H.264/AAC con faststart. Remux sin pérdida primero, transcodificación solo si el códec no es compatible.
whenToUse: Cuando haya que bajar un vídeo de una web (HLS/DASH con cabeceras o cookies de sesión) o convertir MKV/WebM/TS a MP4 antes de publicarlo.
---

# Captura y ensamblado de flujos

Dos niveles de procesamiento para no quemar CPU: **remux** cuando el flujo ya es compatible y
**transcodificación** solo cuando el códec no lo es.

## A. HLS (`.m3u8` / `.ts`)

1. Se descarga el manifiesto con las cabeceras y cookies de sesión del navegador.
2. Si es un *master playlist*, se elige la variante de mayor `BANDWIDTH`.
3. Se descargan los segmentos (`.ts`, o `.m4s` con `#EXT-X-MAP`) en orden.
4. Se concatenan con el demuxer `concat` de ffmpeg y se reempaquetan a H.264 + AAC + faststart.

```bash
scripts/hls-fetch.sh 'https://cdn.ejemplo.com/master.m3u8' salida.mp4 \
  --referer 'https://ejemplo.com/' \
  --cookie 'session=abc123; token=xyz' \
  --ua 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
```

Cabeceras: las que use el navegador en la petición del `.m3u8` (pestaña *Network* → *Copy as
cURL*). Sin `Referer`/`Cookie` correctos el CDN devuelve 403 o un manifiesto vacío.

HLS **cifrado AES-128** o *byte-range*: el modo `--direct` deja que ffmpeg resuelva el manifiesto
completo (descarga, desencripta y remuxea en una pasada):

```bash
scripts/hls-fetch.sh 'https://cdn/master.m3u8' salida.mp4 --direct --cookie '...'
```

## B. DASH / fMP4 (`.mpd` / `.m4s`)

Los fragmentos CMAF (`.m4s`) son `moof`+`mdat` consecutivos: se ensamblan **concatenando
bytes** y luego se remuxea a MP4 con la cabecera al principio (sin pérdida, sin recodificar):

```bash
cat init.mp4 seg-1.m4s seg-2.m4s seg-3.m4s > raw.mp4
ffmpeg -y -i raw.mp4 -c copy -movflags +faststart salida.mp4
```

```bash
scripts/dash-remux.sh salida.mp4 init.mp4 seg-1.m4s seg-2.m4s seg-3.m4s
```

El primer argumento de medios debe ser el **init segment** (`#EXT-X-MAP` o la `Representation`
del `.mpd`). Si el remux falla (fragmentos con `tfdt` discontinuo), usa el manifiesto:

```bash
scripts/dash-remux.sh salida.mp4 --mpd 'https://cdn/manifest.mpd' --cookie '...'
```

> **Por qué no `-f concat` con fMP4**: el demuxer `concat` de ffmpeg no interpreta el `moof`
> de cada fragmento y devuelve un archivo de ~300 bytes con duración 0 (verificado). El
> pipeline `concat.txt` + `-c copy` sí funciona con segmentos **MPEG-TS**, que es el caso A;
> el script lo mantiene como fallback cuando no hay init segment.

## C. Descarga directa y MKV / WebM (`convert_to_mp4`)

Origen único, MKV, WebM (VP9/AV1) o MPEG-TS disfrazado:

**Paso 1 — remux ultra-rápido** (si el vídeo ya es H.264): copia el flujo y recodifica solo el
audio.

```bash
ffmpeg -y -i input -c:v copy -c:a aac -movflags +faststart output.mp4
```

**Paso 2 — fallback** (VP9, AV1, HEVC, MPEG-2…): transcodificación completa con el perfil
universal.

```bash
ffmpeg -y -i input -c:v libx264 -preset veryfast -crf 22 -c:a aac -b:a 192k -movflags +faststart output.mp4
```

El script decide solo, comprobando el códec con `ffprobe` antes de elegir:

```bash
scripts/convert_to_mp4.sh entrada.webm salida.mp4
```

## Binarios de FFmpeg (NAS)

Orden de búsqueda, igual en todos los scripts:

1. `$FFMPEG`
2. `ffmpeg7` (SynoCommunity, en `PATH`)
3. `/usr/local/bin/ffmpeg7`
4. `/volume1/@appstore/ffmpeg/bin/ffmpeg`
5. `/usr/bin/ffmpeg`
6. `ffmpeg` del `PATH`

En el DS124 conviene `export FFMPEG=/usr/local/bin/ffmpeg7`: el ffmpeg de DSM va viejo y sin
`libx264`.

## Límites conocidos

- **DRM (Widevine/PlayReady)**: no se descarga. Ningún script lo intenta.
- **Segmentos con `EXT-X-BYTERANGE`**: usa `--direct`.
- **Audio separado en DASH** (`audio/mp4` aparte): descarga también esa representación y
  móntala con `-map`; `dash-remux.sh` solo se ocupa de una pista.
- **HLS con `#EXT-X-MAP`**: el script detecta el init segment y concatena bytes (ver B); si no
  lo detecta, cae al demuxer `concat` y, si falla, transcodifica.

## Verificación

Siempre después:

```bash
../video-encoding-universal/scripts/verify-mp4.sh salida.mp4
```
