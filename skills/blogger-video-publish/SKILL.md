---
name: blogger-video-publish
description: Publica vídeos en Blogger con reproductor incrustado (Google Drive o YouTube), contenedor responsive 16:9, verificación del HTML servido y del estado de la entrada vía MCP.
whenToUse: Cuando haya que crear o actualizar una entrada de Blogger que contenga un vídeo, o revisar por qué un vídeo incrustado no se reproduce.
---

# Publicar vídeo en Blogger

## 1. Preparar el archivo

El vídeo debe cumplir el perfil universal antes de subirlo (MP4 H.264/AAC, `faststart`).
Usa la skill `video-encoding-universal`:

```bash
scripts/to-mp4.sh original.mkv video.mp4   # o convert_to_mp4.sh si viene de un flujo
scripts/verify-mp4.sh video.mp4 original.mkv
```

## 2. Elegir alojamiento

| | Google Drive | YouTube |
| --- | --- | --- |
| Coste | Gratis con tu cuenta | Gratis |
| Límite | ~5 TB, pero **cuota de reproducción** por archivo | Sin cuota por archivo |
| Vídeo "popular" | Puede devolver «se ha superado el límite de reproducciones» | Sin problema |
| Privacidad | Solo quienes tengan el enlace | Público / no listado |
| Recomendado para | Vídeos personales, pocas visitas | Blog público, tráfico real |

Regla práctica: si la entrada va a recibir visitas, sube a YouTube (no listado si no quieres
que aparezca en búsquedas) y usa el embed de YouTube. Drive vale para compartir con la familia.

## 3. Obtener la URL de incrustación

Drive: el enlace normal **no** sirve; hace falta la variante `/preview`.

```bash
scripts/drive-embed-url.sh 'https://drive.google.com/file/d/1vXvWibmSM4jMjjEfAKwvAy5tOhmq4ZLb/view?usp=sharing'
# → https://drive.google.com/file/d/1vXvWibmSM4jMjjEfAKwvAy5tOhmq4ZLb/preview

scripts/drive-embed-url.sh '<url>' --html    # imprime el bloque listo para pegar
```

YouTube: de `https://youtu.be/ID` o `https://www.youtube.com/watch?v=ID` sale
`https://www.youtube.com/embed/ID`.

## 4. HTML del reproductor

Contenedor responsive 16:9 que Blogger respeta tal cual (verificado: conserva `style`,
`allow` y `allowfullscreen`):

```html
<div style="position:relative;width:100%;max-width:800px;margin:0 auto;padding-bottom:56.25%;height:0;overflow:hidden;">
  <iframe src="https://drive.google.com/file/d/1vXvWibmSM4jMjjEfAKwvAy5tOhmq4ZLb/preview"
          style="position:absolute;top:0;left:0;width:100%;height:100%;border:0;"
          allow="autoplay; fullscreen" allowfullscreen="allowfullscreen"></iframe>
</div>
```

`padding-bottom` según proporción: 16:9 → `56.25%`, 9:16 → `177.78%`, 4:3 → `75%`, 1:1 → `100%`.

## 5. Publicar por MCP

Herramientas del servidor `blogger` (`mcp__blogger__*`):

```
blogger_create_post  { title, content, labels, isDraft }
blogger_update_post  { postId, title?, content?, labels? }
blogger_delete_post  { postId }
blogger_list_posts   { limit }
```

Flujo recomendado:

1. `blogger_create_post` con `isDraft: true` → revisa la URL del borrador en Blogger.
2. `blogger_update_post` para corregir lo que haga falta.
3. Publicar: llamar otra vez con `isDraft: false` no cambia un borrador; usa
   `blogger_update_post` y luego publica desde la UI, o crea directamente publicado.
4. Verifica siempre con `blogger_list_posts` (estado y URL) y con una petición HTTP a la URL
   pública buscando el `<iframe>`.

## 6. Verificación obligatoria

```bash
# el iframe sobrevive al saneador de Blogger
curl -sS 'https://TU.blogspot.com/2026/10/slug.html' | grep -o '<iframe[^>]*>'
```

Comprueba también:

- El archivo de Drive abre en incógnito (uso compartido «cualquiera con el enlace»).
- `Content-Type: video/mp4` y tamaño < 100 MB si vas a usar Drive con frecuencia.
- La entrada tiene etiqueta (`vídeo`) y título descriptivo, no solo el nombre del archivo.

## 7. Problemas típicos

| Síntoma | Causa | Solución |
| --- | --- | --- |
| «Se ha superado el límite de reproducciones» | Cuota de Drive agotada por archivo | Mover a YouTube |
| Marco en blanco con icono de Drive | Archivo privado | Compartir como «cualquiera con el enlace» |
| «No se puede reproducir este vídeo» | Códec no compatible (VP9/AV1 en MP4) | Repasar perfil universal |
| iframe desaparece al guardar | Se pegó en modo HTML pero Blogger lo interpretó como texto | Pegar en vista HTML y comprobar el fuente |
| Se ve borroso en móvil | `width` fijo en px | Usar el contenedor responsive |

## Referencias

- [references/embed.md](references/embed.md): URLs, proporciones y detalles por plataforma.
