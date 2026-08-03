# SubFix

App de macOS que deja los subtítulos de tus películas listos para un televisor que no se lleva bien con ellos.

## Para quién es

Para quien descarga sus películas, las ve **en su idioma original con subtítulos** y las reproduce desde un disco USB conectado al televisor.

Si tu tele es de **2019 o de esos años**, seguramente te ha pasado esto: eliges una película, el menú de subtítulos te muestra las opciones, seleccionas la de español… y no aparece nada en pantalla. O aparece, pero las tildes y las eñes salen convertidas en símbolos raros. Con las películas de hace unos años funcionaba y ahora falla cada vez más a menudo.

No es que el televisor se haya estropeado ni que le falte una actualización: los fabricantes dejaron de dar soporte a esos modelos y su firmware se quedó congelado, mientras que lo que descargamos hoy —4K, HDR, empaquetado en MP4 en lugar de MKV— trae los subtítulos en formatos que ese firmware nunca aprendió a leer.

SubFix se salta el problema por completo: saca el subtítulo a un archivo aparte, con el formato exacto que esos televisores sí entienden.

## El problema técnico

Nació de un caso concreto: un **Samsung RU7400** que lista los subtítulos incrustados en el menú y luego no pinta nada. El reproductor Tizen de esos modelos no trae decodificador para `mov_text` (el subtítulo de los MP4 que salen de iTunes) ni para ASS/SSA dentro de un MKV. Sí lee un archivo `.srt` externo — pero solo si cumple tres condiciones que ninguna herramienta respeta por defecto.

## Las tres condiciones

1. **El `.srt` debe llamarse exactamente como el vídeo.** `pelicula.mkv` → `pelicula.srt`. Un `pelicula.es.srt` el televisor lo trata como archivo ajeno y ni lo ofrece, aunque Plex, Infuse y VLC lo acepten sin problema.
2. **BOM UTF-8** (`EF BB BF`). Sin él, el firmware adivina la codificación, cae en Latin-1 y las tildes, la `ñ`, los `¿` y los `¡` salen convertidos en basura.
3. **Saltos de línea CRLF.** ffmpeg escribe LF de Unix; el televisor espera los de Windows.

SubFix aplica las tres siempre, venga el subtítulo de donde venga.

## Qué hace

Para cada película busca subtítulo en español en tres niveles y se queda con el primero que sirva:

1. **Pista de texto incrustada** — SRT, ASS o `mov_text`. Prefiere la latina y descarta las forzadas y las de subtítulos para sordos, salvo que sean lo único que hay.
2. **Archivo `.srt` o `.ass` suelto** de la carpeta o de un subdirectorio `Subs/`, corrigiéndole la codificación. Un suelto que no lleve el nombre del vídeo solo se adopta si es la única película de la carpeta: con varias juntas, adivinar significa ponerle a una los diálogos de otra.
3. **OpenSubtitles** — primero por *hash* del archivo, que identifica tu versión exacta y llega sincronizado; si no aparece, por título, avisando de que conviene revisar la sincronía.

Además:

- **Repara los `.srt` que ya están** junto a la película. Los que vienen con las descargas suelen estar en Latin-1 y sin CRLF, que es justo lo que se ve como caracteres raros. El original nunca se pisa: se guarda como `.srt.anterior`.
- **Quita la publicidad** que los subtituladores incrustan en el primer y último bloque, y renumera lo que queda. Solo mira esos dos extremos, para no borrar diálogo por un falso positivo.
- **Avisa cuando no puede.** Si la película solo trae subtítulos de imagen (PGS de Blu-ray, VobSub de DVD) y OpenSubtitles no tiene nada, lo dice claramente: eso necesita OCR y SubFix no lo hace.
- **Limpia los archivos fantasma `._` ** que macOS deja en los discos exFAT.

## Cómo se usa

**Películas** — arrastras archivos o una carpeta entera. Antes de tocar nada te muestra qué piensa hacer con cada una, y si hay varias pistas de texto puedes cambiar la elegida.

**Vigilar carpeta** — le señalas tu carpeta de descargas y se encarga sola. Repasa cada 30 segundos, espera a que el archivo deje de crecer para no procesar una descarga a medias, y avisa con una notificación.

## Compilar

Necesitas macOS 14 o posterior y las herramientas de línea de comandos de Xcode.

```sh
./herramientas/compilar_ffmpeg.sh   # una vez: ffmpeg y ffprobe propios
./build_app.sh                      # compila, firma e instala en /Applications
swift run subfixtests               # 24 pruebas
```

`build_app.sh` firma con una identidad local llamada `snapsis-dev`. Si no la tienes, cae a firma ad-hoc y funciona igual; cambia la variable `IDENTIDAD` por la tuya si quieres firma estable.

Para redibujar el icono, que está hecho por código y no con un editor de imágenes:

```sh
swift herramientas/hacer_icono.swift --variantes   # lámina para comparar fondos
swift herramientas/hacer_icono.swift --paleta 3    # genera el .icns
```

## ffmpeg va dentro

La app **no necesita Homebrew**: lleva su propio ffmpeg y ffprobe, compilados solo con los demuxers de contenedor y los códecs de subtítulo que usa. Son 2,6 MB entre los dos, sin ninguna dependencia fuera de `/usr/lib`, y la app entera pesa menos de 4 MB.

Copiar los binarios de Homebrew habría significado arrastrar más de treinta librerías dinámicas —x265, SVT-AV1, VMAF, OpenSSL— que esta app no toca jamás: unos 200 MB y rutas que reescribir a mano.

Como no entra x264 ni x265, lo que se empaqueta es **LGPL 2.1** y no GPL. La licencia de FFmpeg se copia dentro del bundle.

## Estructura

```
Sources/SubFixKit   motor: sondeo, extracción, formato para el TV, OpenSubtitles
Sources/SubFixUI    las vistas
Sources/SubFix      el ejecutable, que solo abre la ventana
Sources/subfixtests pruebas, con arnés propio
herramientas/       compilar ffmpeg y dibujar el icono
```

## Licencia

Código bajo licencia [MIT](LICENSE). FFmpeg, que se empaqueta en el `.app`, es LGPL 2.1 — su licencia viaja dentro del bundle.
