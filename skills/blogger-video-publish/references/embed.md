# Embed de vídeo: URLs y proporciones

## Google Drive

| Enlace | Uso |
| --- | --- |
| `https://drive.google.com/file/d/ID/view?usp=sharing` | Compartir con personas |
| `https://drive.google.com/file/d/ID/preview` | **Incrustar** (iframe) |
| `https://drive.google.com/uc?export=download&id=ID` | Descarga directa |

El ID son 25–44 caracteres `[A-Za-z0-9_-]`.

Para que el iframe funcione con visitantes anónimos, el archivo debe estar compartido como
«Cualquier persona con el enlace» (*Anyone with the link*). Se comprueba sin sesión:

```bash
curl -sSI 'https://drive.google.com/uc?export=download&id=ID' | head -n 5
# 200 o 303 → público; 302 a accounts.google.com → privado
```

Drive limita las reproducciones por archivo y por franja de tiempo. Pasado el umbral, el
iframe muestra «Se ha superado el límite de reproducciones de este vídeo». No hay forma de
subir ese límite: hay que mover el vídeo a YouTube.

## YouTube

| Enlace | Embed |
| --- | --- |
| `https://youtu.be/ID` | `https://www.youtube.com/embed/ID` |
| `https://www.youtube.com/watch?v=ID` | `https://www.youtube.com/embed/ID` |
| `https://www.youtube.com/shorts/ID` | `https://www.youtube.com/embed/ID` |

Opciones útiles del embed:

- `?rel=0` — no sugerir vídeos de otros canales al terminar.
- `?modestbranding=1` — menos marca (obsoleto en parte).
- `?start=90` — empezar en el segundo 90.
- `?cc_load_policy=1` — subtítulos activados.

Conviene añadir `title="..."` al iframe: es el nombre accesible del reproductor.

## Proporciones y `padding-bottom`

| Proporción | `padding-bottom` | Cuándo |
| --- | --- | --- |
| 16:9 | `56.25%` | Horizontal estándar (por defecto) |
| 9:16 | `177.78%` | Vertical de móvil / Shorts |
| 4:3 | `75%` | Material antiguo |
| 1:1 | `100%` | Cuadrado |

## Plantilla mínima

```html
<div style="position:relative;width:100%;max-width:800px;margin:0 auto;padding-bottom:56.25%;height:0;overflow:hidden;">
  <iframe src="URL_DEL_REPRODUCTOR"
          title="Descripción del vídeo"
          style="position:absolute;top:0;left:0;width:100%;height:100%;border:0;"
          allow="autoplay; fullscreen; picture-in-picture"
          allowfullscreen="allowfullscreen"
          loading="lazy"></iframe>
</div>
```

`loading="lazy"` retrasa la carga del reproductor hasta que el lector se acerca: mejora mucho
el LCP de la entrada.

## Qué conserva Blogger

Verificado en una entrada real de `areasww.blogspot.com`:

- `<iframe>`, `src`, `style`, `allow`, `allowfullscreen`, `title`, `loading` — se conservan.
- `<script>` — se elimina (no se puede usar JS propio en una entrada).
- Atributos `on*` — se eliminan.

Si el iframe no aparece en el HTML servido, se pegó como texto: hay que usar la vista **HTML**
del editor de Blogger, no la vista de composición.
