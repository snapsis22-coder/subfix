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
3. **OpenSubtitles** — primero por *hash* del archivo, que identifica tu versión exacta y llega sincronizado; si no aparece, por título.

**Comprueba que vaya sincronizado.** Lo que se baja de internet (Addic7ed, OpenSubtitles, Subdivx) suele ser de otra versión del video. Antes de ponerlo, SubFix lo compara con algo que seguro va con tu archivo: un subtítulo que el video ya traiga dentro (casi siempre el inglés; aunque sea otro idioma, las frases entran y salen a la vez) o, si no trae ninguno, el **audio**: escucha cuatro tramos de unos minutos del canal central, donde va la voz, y marca dónde se habla. Con eso:

- si va sincronizado, lo pone y lo dice («sincronía comprobada con el audio de la película»);
- si está corrido lo mismo en toda la película, o se hizo para 25 fps, **lo corrige** y lo pone;
- si cada parte de la película pide otra cosa (otro montaje, escenas de más) o no se parece en nada, **no lo pone** y prueba el siguiente. Si ninguno sirve, la fila queda en naranja.

Un corrimiento chico medido contra otro subtítulo se confirma con el audio, porque dos subtítulos buenos del mismo video pueden diferir medio segundo. Para calibrarlo con tus películas: `swift run subfixsync <video> <subtítulo.srt>`.

**Preferir latino.** Los capítulos de series (los que llevan `S01E01` en el nombre) suelen traer incrustado solo el español de España. Con la casilla *Preferir latino* activada, antes que la pista incrustada se busca el español latino en **Addic7ed**, eligiendo la versión que más se parece al nombre de tu archivo, que es la que va sincronizada. Lo que se descarga se comprueba: si en realidad está en inglés (a veces lo suben mal etiquetado), se descarta.

**El de España, solo si tú lo apruebas.** SubFix reconoce el español de España por el *vosotros* («sois», «os», «tenéis»). Si para una película o capítulo solo aparece ese, no lo pone: la fila se queda en naranja con el botón **Usar el de España**, por si lo prefieres a nada. Lo mismo comprueba el idioma de verdad: un subtítulo en inglés o en francés mal etiquetado como latino se descarta.

**Subdivx dentro de la app.** Para los que quedan sin latino, el botón **Subdivx** abre el sitio en una ventana de SubFix, a la vista. La verificación de Cloudflare la pasas tú si la pide; después SubFix busca cada capítulo o película (con el año, para no confundir películas con el mismo nombre), y va bajando sus resultados, del más probable al menos (hasta cinco), hasta dar con uno **latino y sincronizado**; lo limpia y lo deja puesto, uno tras otro. Si es latino o de España lo decide leyendo el texto (el *vosotros*), no por cómo se llama el archivo, y de un paquete con varias versiones se queda con la que va con tu video. Con la opción *Buscar en Subdivx los que queden sin latino*, esa ventana se abre sola al terminar de procesar.

**También puedes arrastrar lo que bajes de Subdivx.** El `.zip`, `.rar` o `.srt` se suelta en la ventana: SubFix lo abre (también los `.zip` con nombres en la codificación vieja de DOS, tan comunes en Subdivx), empareja cada subtítulo con su capítulo por el `S01E02`, elige el latino si vienen los dos, lo limpia, lo deja con el nombre del video y lo mete en su carpeta.

Además:

- **Repara los `.srt` que ya están** junto a la película. Los que vienen con las descargas suelen estar en Latin-1 y sin CRLF, que es justo lo que se ve como caracteres raros. El original nunca se pisa: se guarda como `.srt.anterior`.
- **Quita la publicidad** que los subtituladores incrustan en el primer y último bloque, y renumera lo que queda. Solo mira esos dos extremos, para no borrar diálogo por un falso positivo.
- **Limpia las etiquetas de formato ASS.** Esas pistas llevan instrucciones entre llaves: `{\an8}` sube la línea para que no tape algo que ya está en pantalla, `{\i1}` la pone en cursiva, `{\pos(x,y)}` la coloca en un punto exacto. VLC e Infuse las obedecen; un televisor viejo no las conoce y las imprime tal cual, así que en pantalla se lee `{\an8}Calma, Caraxes.`. Se borran solo las llaves cuyo contenido empieza por barra invertida, así que un diálogo que legítimamente diga `{algo}` se queda intacto.
- **Depura los caracteres basura.** Quita las etiquetas HTML (`<i>`, `<font color=…>`), los caracteres invisibles (espacios de ancho cero, marcas de dirección, guiones blandos), compone las tildes que vienen separadas de su letra y deshace el texto doblemente codificado (`Ã©` → `é`). Un `<3` o un `#hashtag` del diálogo se quedan como están.
- **Avisa cuando no puede.** Si la película solo trae subtítulos de imagen (PGS de Blu-ray, VobSub de DVD) y OpenSubtitles no tiene nada, lo dice claramente: eso necesita OCR y SubFix no lo hace.
- **Limpia los archivos fantasma `._` ** que macOS deja en los discos exFAT.

**Reprocesar.** ¿Quedó un subtítulo desfasado o equivocado? **Reprocesar** (en la fila o en su menú) busca otro sin vaciar la lista: el que tiene queda marcado como rechazado y no vuelve a elegirse, venga de donde venga, y solo se aparta como `.srt.anterior` si aparece uno mejor. Si no aparece, se queda el de antes y la fila lo dice.

**Pestaña Pistas.** Muestra qué audios y subtítulos trae cada película y cuál sale sola al abrirla (★). Desde cualquier fila de *Subtítulos*, **Modificar pistas…** la lleva ahí. **Editar pistas…** abre una hoja para armar un `.mkv` nuevo a tu medida: qué audios se quedan, qué subtítulos del archivo se conservan, qué `.srt`, `.zip` o `.rar` se añaden (por ejemplo el de Subdivx), cómo se llama el archivo y en qué idioma se rotula cada pista, con una lista desplegable de idiomas. Cada subtítulo del archivo tiene su botón **Extraer .srt** por si lo quieres suelto. Se crea en el acto, con una barra de progreso verde. No recodifica nada (copia el video y el audio tal cual, y conserva capítulos y adjuntos), conserva las marcas de tiempo del video y **nunca toca ni pisa el original**: si el nombre ya existe, añade «(2)». El MKV nuevo se agrega a la lista para que veas cómo quedó. Sirve, por ejemplo, para quitar un audio sobrante o para bajar las 38 pistas de un capítulo por debajo del límite que aguanta el televisor.

**Extraer latino.** Un botón para toda la lista que hace solo esto, sin internet: saca del propio archivo el subtítulo latino, lo limpia (publicidad, etiquetas, caracteres raros) y lo deja como `.srt` junto al video, que es el que el televisor pone solo. Al terminar mete cada capítulo en su carpeta. Si ya había un `.srt`, se aparta como `.srt.anterior`; si el archivo solo trae el de España, no lo pone sin preguntarte.

**Latino por defecto.** También en *Pistas*, para una película o para toda la lista: deja como automático el subtítulo latino que el MKV trae dentro y, solo si el archivo trae doblaje latino, también ese audio. No crea otro archivo ni reescribe el video: cambia únicamente la marca «por defecto» de cada pista en la cabecera del MKV, como `mkvpropedit`, en un segundo y sin ocupar espacio. Antes guarda una copia de esos bytes en `~/Library/Application Support/SubFix/Cabeceras/` y, al terminar, vuelve a leer el archivo para comprobar que quedó bien; si no, lo deja como estaba. Funciona con los MKV de mkvmerge, que es como llegan casi todas las descargas; si a un archivo no le queda espacio libre en la cabecera, avisa y no lo toca.

## Cómo se usa

**Películas** — arrastras archivos o una carpeta entera (también lee sus subcarpetas, por si la temporada ya está organizada por capítulo), o los eliges con **Añadir…** (⌘O). Además revisa sola tu carpeta de descargas cada vez que abres la pestaña y trae los videos nuevos, saltándose lo que todavía se está bajando; la carpeta se cambia con el botón de la izquierda de la barra inferior. La lista se agrupa por serie y temporada, y antes de tocar nada te muestra qué piensa hacer con cada una. **Procesar** busca el latino en internet; para sacarlo también de la pista del archivo, enciende *Extraer del archivo* en el menú **Opciones**, que recuerda lo que elijas.

**Organizar en carpetas** mete cada capítulo con su `.srt` en una subcarpeta propia (`Ted Lasso S01E01/`), y lo mismo hace *Carpeta por capítulo* en **Opciones** al terminar de procesar. Dentro del mismo disco es un renombrado instantáneo y nunca se pisa nada.

**Organizar** — ordena las descargas en la estructura que entienden Jellyfin y Plex: cada película a `Películas/Título (Año)/Título (Año).mkv` y cada capítulo a `Series/Serie/Season 01/Serie S01E02.mkv`, con sus `.srt` y `.nfo`, que cambian de nombre con él. El nombre con el que se bajó no se pierde: queda en «Dónde se obtuvo» (Obtener información) y, en los MKV, dentro del archivo como etiqueta `NOMBRE_ORIGINAL`, escrita en el espacio libre de la cabecera sin reescribir el video. No va en el título, que es lo que muestran el televisor y Jellyfin. Lee el título, el año y el `S01E02` del nombre del archivo o de su carpeta, te muestra a dónde va cada uno antes de mover nada, y si lee mal un nombre lo corriges con el lápiz. Si el destino ya existe, no lo toca. **Deshacer** devuelve el último lote a su sitio, y con **Automático** repasa la carpeta cada 30 segundos y avisa con una notificación.

## Actualizaciones

SubFix se actualiza desde sus Releases de GitHub. Al abrir, como mucho una vez al día, mira si hay una versión nueva y lo avisa con una franja; solo instala cuando pulsas **Actualizar**, y no mientras está procesando u organizando. Antes de cambiar nada comprueba que el DMG coincida con el hash que publica GitHub y que la app nueva esté firmada con el mismo certificado que la instalada. La versión vieja va a la Papelera. Como la descarga la hace la app y no el navegador, macOS no vuelve a pedir «Abrir de todos modos». También está en el menú **SubFix › Buscar actualizaciones…**.

## Compilar

Necesitas macOS 14 o posterior y las herramientas de línea de comandos de Xcode.

```sh
./herramientas/compilar_ffmpeg.sh   # una vez: ffmpeg y ffprobe propios
./build_app.sh                      # compila, firma e instala en /Applications
swift run subfixtests               # 150 pruebas (SUBFIX_PROBAR_RED=1 incluye la descarga real)
```

`build_app.sh` firma con una identidad local llamada `snapsis-dev`. Si no la tienes, cae a firma ad-hoc y funciona igual; cambia la variable `IDENTIDAD` por la tuya si quieres firma estable.

Para redibujar el icono, que está hecho por código y no con un editor de imágenes:

```sh
swift herramientas/hacer_icono.swift --variantes   # lámina para comparar fondos
swift herramientas/hacer_icono.swift --paleta 3    # genera el .icns
```

## ffmpeg va dentro

La app **no necesita Homebrew**: lleva su propio ffmpeg y ffprobe, compilados solo con los contenedores, los códecs de subtítulo y el muxer de Matroska que usa. Son unos 8 MB entre los dos —incluyen los decodificadores de video que ffmpeg necesita para copiar bien los fotogramas B—, sin ninguna dependencia fuera de `/usr/lib`, y la app entera pesa menos de 10 MB.

Copiar los binarios de Homebrew habría significado arrastrar más de treinta librerías dinámicas —x265, SVT-AV1, VMAF, OpenSSL— que esta app no toca jamás: unos 200 MB y rutas que reescribir a mano.

Como no entra x264 ni x265, lo que se empaqueta es **LGPL 2.1** y no GPL. La licencia de FFmpeg se copia dentro del bundle.

## Estructura

```
Sources/SubFixKit   motor: sondeo, extracción, formato para el TV, OpenSubtitles, Addic7ed, subtítulos bajados a mano
Sources/OrganizarKit lectura de nombres y plan para ordenar películas y series
Sources/SubFixUI    las vistas
Sources/SubFix      el ejecutable, que solo abre la ventana
Sources/subfixtests pruebas, con arnés propio
herramientas/       compilar ffmpeg y dibujar el icono
```

## Licencia

Código bajo licencia [MIT](LICENSE). FFmpeg, que se empaqueta en el `.app`, es LGPL 2.1 — su licencia viaja dentro del bundle.
