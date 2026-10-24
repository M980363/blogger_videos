# blogger_videos

Skills de DSH para **publicar vídeo en Blogger** con un perfil de codificación único y
reproducible en Synology DS124, navegadores y Smart TVs.

Cada skill es un bundle autocontenido (`SKILL.md` + `scripts/` + `references/`) que el agente
carga bajo demanda. Los scripts son POSIX `sh`/`bash` y no dependen de nada fuera de `ffmpeg`,
`ffprobe`, `curl` y utilidades estándar.

## Skills

| Skill | Para qué |
| --- | --- |
| [`video-encoding-universal`](skills/video-encoding-universal/SKILL.md) | Dejar cualquier vídeo en MP4 H.264/AAC (CRF 22, `veryfast`, `faststart`, `avc1`) y verificarlo con `ffprobe`. |
| [`video-stream-capture`](skills/video-stream-capture/SKILL.md) | Bajar HLS (`.m3u8`/`.ts`), ensamblar DASH/fMP4 (`.m4s`) y convertir MKV/WebM/TS a MP4 con remux primero y transcodificación como fallback. |
| [`blogger-video-publish`](skills/blogger-video-publish/SKILL.md) | Publicar el vídeo en Blogger con reproductor incrustado (Drive o YouTube), verificar el HTML servido y las etiquetas. |

## Instalación local (DSH)

DSH descubre skills en `<proyecto>/.dsh/skills/<nombre>/SKILL.md` y en `~/.dsh/skills/<nombre>/`.
Este repo se enlaza sin duplicar contenido:

```powershell
# Windows (junction, sin permisos de administrador)
$repo = "C:\Users\m9803\Desktop\extensiones\blogger_areas\blogger_videos\skills"
foreach ($s in Get-ChildItem $repo -Directory) {
  New-Item -ItemType Junction -Path "$env:USERPROFILE\.dsh\skills\$($s.Name)" -Target $s.FullName
}
```

```bash
# Linux / macOS / Synology
for s in skills/*/; do ln -s "$PWD/$s" ~/.dsh/skills/"$(basename "$s")"; done
```

El proveedor vigila el directorio: las skills aparecen en el catálogo sin reiniciar.

Como alternativa sin enlaces, copia `skills/<nombre>` a `~/.dsh/skills/`.

## Uso rápido en el Synology DS124

```bash
# ffmpeg7 de SynoCommunity es el binario preferido
export FFMPEG=/usr/local/bin/ffmpeg7

./skills/video-encoding-universal/scripts/to-mp4.sh entrada.mkv salida.mp4
./skills/video-encoding-universal/scripts/verify-mp4.sh salida.mp4

./skills/video-stream-capture/scripts/hls-fetch.sh 'https://host/master.m3u8' salida.mp4 \
  --referer 'https://host/' --cookie "$COOKIE"

./skills/video-stream-capture/scripts/convert_to_mp4.sh entrada.webm salida.mp4
```

El DS124 tiene **1 núcleo ARM64**: `-preset veryfast` y CRF 22 están elegidos para que una
transcodificación de 10 minutos no bloquee el NAS. Cuando el códec ya es H.264 el script
**remuxea** (copia el flujo, segundos) en lugar de recodificar.

## Dependencias

- `ffmpeg` ≥ 5 (recomendado `ffmpeg7` de SynoCommunity), con `libx264` y `aac`.
- `curl` para HLS/DASH con cabeceras de sesión.
- Opcional: `grep` GNU (para comprobar `faststart`), `python3` no es necesario.

## Verificación

`tests/smoke.sh` genera un vídeo sintético, lo pasa por el perfil universal y comprueba
contenedor, códec, tag `avc1`, `yuv420p`, audio AAC y `faststart`:

```bash
FFMPEG=/c/ffmpeg/bin/ffmpeg.exe bash tests/smoke.sh
```

## Licencia

MIT — ver [LICENSE](LICENSE).
