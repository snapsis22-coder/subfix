import Foundation
import SubFixKit
import SubFixUI

/// Arnés de pruebas propio, igual que en Bóveda: `swift run subfixtests`.
var pasadas = 0, falladas = 0

func probar(_ nombre: String, _ cuerpo: () throws -> Bool) {
    do {
        if try cuerpo() {
            pasadas += 1
            print("  ✅ \(nombre)")
        } else {
            falladas += 1
            print("  ❌ \(nombre)")
        }
    } catch {
        falladas += 1
        print("  ❌ \(nombre) — \(error)")
    }
}

/// Igual que `probar`, para las comprobaciones que tienen que esperar.
func probarEsperando(_ nombre: String, _ cuerpo: () async throws -> Bool) async {
    do {
        if try await cuerpo() {
            pasadas += 1
            print("  ✅ \(nombre)")
        } else {
            falladas += 1
            print("  ❌ \(nombre)")
        }
    } catch {
        falladas += 1
        print("  ❌ \(nombre) — \(error)")
    }
}

// Todo lo que pase por Herramientas usa el ffmpeg MÍNIMO que viaja en la app, no el de Homebrew.
// (Las muestras de prueba se siguen fabricando con el de Homebrew, que sí tiene codificadores.)
let binPropio = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Resources/bin").path
if FileManager.default.fileExists(atPath: binPropio) { setenv("SUBFIX_BIN", binPropio, 1) }

let temporal = FileManager.default.temporaryDirectory
    .appendingPathComponent("subfixtests-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: temporal, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporal) }

print("\n▸ Formato para el TV")

probar("escribe con BOM UTF-8 y CRLF") {
    let destino = temporal.appendingPathComponent("uno.srt")
    try TextoSRT.escribirParaElTV("1\n00:00:01,000 --> 00:00:02,000\n¿Dónde está la niña?\n", en: destino)
    let datos = try Data(contentsOf: destino)
    return datos.starts(with: TextoSRT.bom)
        && datos.range(of: Data([0x0D, 0x0A])) != nil
        && TextoSRT.estaBienFormado(destino)
}

probar("no deja retornos sueltos aunque la fuente mezcle finales de línea") {
    let destino = temporal.appendingPathComponent("dos.srt")
    try TextoSRT.escribirParaElTV("uno\r\ndos\rtres\ncuatro", en: destino)
    let datos = [UInt8](try Data(contentsOf: destino))
    for i in 0..<datos.count where datos[i] == 0x0D {
        if i + 1 >= datos.count || datos[i + 1] != 0x0A { return false }
    }
    return true
}

probar("lee Latin-1 sin romper las tildes") {
    let origen = temporal.appendingPathComponent("latin.srt")
    let texto = "1\n00:00:01,000 --> 00:00:02,000\n¡Añoro el café español!\n"
    try texto.data(using: .windowsCP1252)!.write(to: origen)
    let leido = try TextoSRT.leer(origen)
    return leido.texto.contains("Añoro") && leido.texto.contains("café")
}

probar("un .srt en Latin-1 no se da por bien formado") {
    let origen = temporal.appendingPathComponent("mal.srt")
    try "1\n00:00:01,000 --> 00:00:02,000\nhola\n".data(using: .windowsCP1252)!.write(to: origen)
    return TextoSRT.estaBienFormado(origen) == false
}

probar("apartar no pisa el archivo del usuario") {
    let original = temporal.appendingPathComponent("apartar.srt")
    try "contenido".write(to: original, atomically: true, encoding: .utf8)
    let apartado = try TextoSRT.apartar(original)
    let contenido = try String(contentsOf: apartado, encoding: .utf8)
    return FileManager.default.fileExists(atPath: apartado.path)
        && !FileManager.default.fileExists(atPath: original.path)
        && contenido == "contenido"
}

print("\n▸ Publicidad")

probar("quita el bloque de propaganda del principio y del final") {
    let conSpam = """
    1
    00:00:06,000 --> 00:01:06,000
    -=[ ai.OpenSubtitles.com ]=-

    2
    00:01:19,792 --> 00:01:20,959
    ¡Oye!

    3
    00:01:47,819 --> 00:01:50,488
    Una oscura noche.

    4
    02:49:55,305 --> 02:50:55,568
    ¿Cansado de buscar subtítulos?
    Ray los genera al instante: getray.app
    """
    let (limpio, quitados) = TextoSRT.quitarPublicidad(conSpam)
    return quitados == 2 && limpio.contains("¡Oye!") && !limpio.contains("getray")
}

probar("no toca diálogo legítimo") {
    let bueno = """
    1
    00:00:01,000 --> 00:00:02,000
    ¿Vamos al cine?

    2
    00:00:03,000 --> 00:00:04,000
    Sí, a las ocho.

    3
    00:00:05,000 --> 00:00:06,000
    Te espero.
    """
    let (limpio, quitados) = TextoSRT.quitarPublicidad(bueno)
    return quitados == 0 && limpio == bueno
}

probar("renumera después del recorte") {
    let conSpam = """
    1
    00:00:06,000 --> 00:01:06,000
    www.subdivx.com

    2
    00:01:19,792 --> 00:01:20,959
    Primera de verdad.

    3
    00:01:47,819 --> 00:01:50,488
    Segunda de verdad.
    """
    let (limpio, _) = TextoSRT.quitarPublicidad(conSpam)
    return limpio.hasPrefix("1\n00:01:19")
}

print("\n▸ Etiquetas de formato ASS")

probar("quita {\\an8} y deja el diálogo") {
    let conEtiqueta = """
    1
    00:00:01,000 --> 00:00:03,000
    {\\an8}Calma, Caraxes.
    """
    let (limpio, tocadas) = TextoSRT.quitarEtiquetasASS(conEtiqueta)
    return tocadas == 1 && limpio.contains("Calma, Caraxes.") && !limpio.contains("an8")
}

probar("traduce \\N a salto y \\h a espacio") {
    let crudo = """
    1
    00:00:01,000 --> 00:00:03,000
    {\\i1}Hola\\Nmundo{\\i0}

    2
    00:00:04,000 --> 00:00:05,000
    Se\\hva
    """
    let (limpio, _) = TextoSRT.quitarEtiquetasASS(crudo)
    return limpio.contains("Hola\nmundo") && limpio.contains("Se va") && !limpio.contains("\\N")
}

probar("respeta unas llaves de diálogo legítimo") {
    let crudo = """
    1
    00:00:01,000 --> 00:00:03,000
    Dijo {textual} eso.
    {\\an8}Y esto no.
    """
    let (limpio, _) = TextoSRT.quitarEtiquetasASS(crudo)
    return limpio.contains("{textual}") && !limpio.contains("{\\an8}")
}

probar("descarta el dibujo vectorial y renumera") {
    let crudo = """
    1
    00:00:01,000 --> 00:00:02,000
    {\\p1}m 0 0 l 100 0 100 50 0 50{\\p0}

    2
    00:00:03,000 --> 00:00:04,000
    Diálogo real.
    """
    let (limpio, _) = TextoSRT.quitarEtiquetasASS(crudo)
    return limpio.hasPrefix("1\n00:00:03") && limpio.contains("Diálogo real.")
        && !limpio.contains("l 100 0")
}

probar("un .srt sin etiquetas queda intacto") {
    let bueno = """
    1
    00:00:01,000 --> 00:00:03,000
    Nada que tocar.
    """
    let (limpio, tocadas) = TextoSRT.quitarEtiquetasASS(bueno)
    return tocadas == 0 && limpio == bueno
}

print("\n▸ Caracteres basura")

probar("quita etiquetas HTML e invisibles y compone las tildes") {
    let crudo = "1\n00:00:01,000 --> 00:00:02,000\n<i>¿Quiénes\u{200B} sois?</i>\n<font color=\"#ffff00\">Cafe\u{0301}\u{00A0}solo</font>\n"
    let (limpio, tocadas) = TextoSRT.depurarCaracteres(crudo)
    return tocadas == 2 && limpio.contains("¿Quiénes sois?\nCafé solo")
        && !limpio.contains("<") && !limpio.contains("\u{200B}")
}

probar("deshace el doble codificado (Ã© → é)") {
    let (limpio, _) = TextoSRT.depurarCaracteres("1\n00:00:01,000 --> 00:00:02,000\nÂ¿DÃ³nde estÃ¡ la niÃ±a?\n")
    return limpio.contains("¿Dónde está la niña?")
}

probar("respeta un «<3» y un «#Richmond» del diálogo") {
    let bueno = "1\n00:00:01,000 --> 00:00:02,000\nTe quiero <3, evita #Richmond."
    let (limpio, tocadas) = TextoSRT.depurarCaracteres(bueno)
    return tocadas == 0 && limpio == bueno
}

probar("un bloque que era sólo etiquetas desaparece y se renumera") {
    let crudo = "1\n00:00:01,000 --> 00:00:02,000\n<i></i>\n\n2\n00:00:03,000 --> 00:00:04,000\nHola."
    let (limpio, _) = TextoSRT.depurarCaracteres(crudo)
    return limpio.hasPrefix("1\n00:00:03") && limpio.contains("Hola.")
}

probar("reconoce inglés disfrazado de español, y el español de los dos lados") {
    let ingles = String(repeating: "- Morning, Coach. You wanna grab some breakfast? Nah, I just had one piece of cereal and I'm pretty stuffed.\n", count: 15)
    let latino = String(repeating: "Rupert y yo lo compramos en nuestro quinto aniversario. ¿Qué es eso? Que ustedes llaman futbol a ningún nivel.\n", count: 15)
    let españa = String(repeating: "¿Quiénes sois? Os presento: es Higgins. Cualquier cosa con café vale, parece un tío divertido.\n", count: 15)
    return !TextoSRT.pareceEspañol(ingles) && TextoSRT.pareceEspañol(latino) && TextoSRT.pareceEspañol(españa)
        && TextoSRT.pareceEspañol("1\n00:00:01,000 --> 00:00:02,000\nOK.")     // poco texto: no se juzga
}

let textoEspaña = "1\n00:00:00,000 --> 00:00:00,900\n¿Quiénes sois vosotros?\n\n2\n00:00:01,000 --> 00:00:01,900\nOs lo dije, tío.\n\n3\n00:00:02,000 --> 00:00:02,900\n¿Tenéis hambre?\n\n4\n00:00:03,000 --> 00:00:03,900\n¿Qué queréis?\n\n5\n00:00:04,000 --> 00:00:04,900\nVale, ¿podéis callaros?\n"
let textoLatino = "1\n00:00:00,000 --> 00:00:00,900\n¿Quiénes son ustedes?\n\n2\n00:00:01,000 --> 00:00:01,900\nSe los dije.\n\n3\n00:00:02,000 --> 00:00:02,900\n¿Tienen hambre?\n\n4\n00:00:03,000 --> 00:00:03,900\n¿Qué quieren?\n\n5\n00:00:04,000 --> 00:00:04,900\nEstá bien, ¿se pueden callar?\n"

probar("distingue el español de España del latino") {
    TextoSRT.pareceDeEspaña(textoEspaña) && !TextoSRT.pareceDeEspaña(textoLatino)
        && !TextoSRT.pareceDeEspaña("Tiene dieciséis años y veintiséis primos. Dieciséis. Veintiséis. Dieciséis.")
}

print("\n▸ Subtítulos bajados a mano (Subdivx)")

let bajados = temporal.appendingPathComponent("bajados", isDirectory: true)
try? FileManager.default.createDirectory(at: bajados, withIntermediateDirectories: true)
let srtEspaña = bajados.appendingPathComponent("Show.S01E02.Biscuits (Español (España)).srt")
let srtLatino = bajados.appendingPathComponent("Show.S01E02.Biscuits (Español (Latinoamérica)).srt")
try? textoEspaña.data(using: .windowsCP1252)!.write(to: srtEspaña)       // como llegan de Subdivx
try? textoLatino.data(using: .windowsCP1252)!.write(to: srtLatino)
let zipBajado = temporal.appendingPathComponent("Show S01E02 - [MarcusL].zip")
_ = try? Herramientas.correr("bsdtar", ["-a", "-cf", zipBajado.path, "-C", bajados.path,
                                         srtEspaña.lastPathComponent, srtLatino.lastPathComponent])

probar("abre el .zip y encuentra los dos .srt") {
    Motor.subtitulos(en: [zipBajado]).count == 2
}

probar("una carpeta con videos no se toma por subtítulos (es la serie)") {
    Motor.subtitulos(en: [temporal.appendingPathComponent("serie")]).isEmpty
}

probar("empareja por capítulo y elige el latino aunque venga el de España") {
    let e2 = URL(fileURLWithPath: "/x/Show.S01E02.WEB.mkv"), e3 = URL(fileURLWithPath: "/x/Show.S01E03.WEB.mkv")
    let pares = Motor.emparejar([srtEspaña, srtLatino], con: [e2, e3])
    return pares.count == 1 && pares[0].video == e2 && pares[0].subtitulo == srtLatino
}

probar("la búsqueda para Subdivx") {
    Motor.busquedaSubdivx(para: URL(fileURLWithPath: "/x/Ted.Lasso.S01E02.HDR.2160p.mkv")) == "Ted Lasso S01E02"
        && Motor.busquedaSubdivx(para: URL(fileURLWithPath: "/x/The.Batman.2022.1080p.WEB-DL.mkv")) == "The Batman"
}

print("\n▸ Elección de pista")

let latina = Pista(indice: 4, codec: "ass", idioma: "spa", titulo: "Latino", forzada: false, paraSordos: false)
let forzada = Pista(indice: 3, codec: "subrip", idioma: "spa", titulo: "Forced", forzada: true, paraSordos: false)
let sorda = Pista(indice: 2, codec: "subrip", idioma: "spa", titulo: "España SDH", forzada: false, paraSordos: true)
let inglesa = Pista(indice: 1, codec: "subrip", idioma: "eng", titulo: nil, forzada: false, paraSordos: false)
let pgs = Pista(indice: 5, codec: "hdmv_pgs_subtitle", idioma: "spa", titulo: nil, forzada: false, paraSordos: false)

probar("prefiere la latina sobre la forzada y la de sordos") {
    Sondeo.mejor(entre: [sorda, forzada, latina])?.elegida.indice == 4
}

probar("reconoce el español y descarta el inglés") {
    latina.esEspañol && sorda.esEspañol && !inglesa.esEspañol
}

probar("distingue texto de imagen") {
    latina.esTexto && !latina.esImagen && pgs.esImagen && !pgs.esTexto
}

probar("avisa del empate cuando hay dos iguales") {
    let a = Pista(indice: 2, codec: "subrip", idioma: "spa", titulo: nil, forzada: false, paraSordos: false)
    let b = Pista(indice: 3, codec: "subrip", idioma: "spa", titulo: nil, forzada: false, paraSordos: false)
    return Sondeo.mejor(entre: [a, b])?.huboEmpate == true
}

print("\n▸ Nombres de release")

probar("limpia el nombre de una película") {
    OpenSubtitles.tituloLimpio(URL(fileURLWithPath: "/x/The.Batman.2022.1080p.WEB-DL.DDP5.1.H.264-NTb.mkv")).titulo == "the batman"
}

probar("saca temporada y episodio de una serie") {
    let r = OpenSubtitles.tituloLimpio(URL(fileURLWithPath: "/x/House.of.the.Dragon.S03E07.2160p.HMAX.WEB-DL.mkv"))
    return r.titulo == "house of the dragon" && r.temporada == 3 && r.episodio == 7
}

probar("el .srt se llama exactamente como el video") {
    Motor.destinoSRT(de: URL(fileURLWithPath: "/x/Peli [2026]+.mp4")).lastPathComponent == "Peli [2026]+.srt"
}

probar("ignora los archivos fantasma ._ de exFAT") {
    let carpeta = temporal.appendingPathComponent("exfat")
    try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    try Data().write(to: carpeta.appendingPathComponent("peli.mkv"))
    try Data().write(to: carpeta.appendingPathComponent("._peli.mkv"))
    return Motor.videos(en: [carpeta]).count == 1
}

print("\n▸ OpenSubtitles")

probar("el hash necesita al menos 128 KB de archivo") {
    let chico = temporal.appendingPathComponent("chico.mkv")
    try Data(repeating: 0, count: 1000).write(to: chico)
    return try OpenSubtitles.hash(de: chico) == nil
}

probar("el hash coincide con una implementación independiente") {
    // Archivo determinista: byte[i] = i % 251. El valor esperado se calculó
    // aparte en Python siguiendo la especificación de OpenSubtitles, así que
    // esto compara dos implementaciones, no la función consigo misma.
    let ruta = temporal.appendingPathComponent("hash.mkv")
    let datos = Data((0..<200_000).map { UInt8($0 % 251) })
    try datos.write(to: ruta)
    return try OpenSubtitles.hash(de: ruta) == "e19d5212c9812cd6"
}

probar("descomprime un .gz igual que gunzip") {
    let plano = "1\n00:00:01,000 --> 00:00:02,000\n¿Añoramos el café?\n"
    let origen = temporal.appendingPathComponent("prueba.txt")
    try plano.write(to: origen, atomically: true, encoding: .utf8)

    let gzip = Process()
    gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
    gzip.arguments = ["-k", "-f", origen.path]
    try gzip.run(); gzip.waitUntilExit()

    let comprimido = try Data(contentsOf: temporal.appendingPathComponent("prueba.txt.gz"))
    guard let descomprimido = OpenSubtitles.descomprimirGzip(comprimido) else { return false }
    return String(data: descomprimido, encoding: .utf8) == plano
}

print("\n▸ Addic7ed y carpetas por capítulo")

// Recorte real de la página de Ted Lasso 1x05 filtrada por latino, con dos versiones.
let paginaAddic7ed = """
<td colspan="3" align="center" class="NewsTitle"><img />Version BTW+ION10+NOGRP+R.I.P.SCENE, Duration: 0.00 </td>
<td width="21%" class="language">Spanish (Latin America)<a href="javascript:saveFavorite(160075,6,1)"></a></td>
<td width="19%"><b>Completed </b> </td><td colspan="3"><a class="face-button" href="/original/160075/72">
<img title="Corrected" /><img title="Hearing Impaired" />0 times edited · 455 Downloads · 618 sequences
<td colspan="3" align="center" class="NewsTitle"><img />Version ATVP.WEB-DL-NTb, Duration: 0.00 </td>
<td width="21%" class="language">Spanish (Latin America)</td>
<td width="19%"><b>35.42% Completed</b> </td><td colspan="3"><a class="face-button" href="/original/160075/32">
0 times edited · 12 Downloads · 618 sequences
"""

probar("lee las versiones de la página de Addic7ed") {
    let v = Addic7ed.versiones(en: paginaAddic7ed)
    return v.count == 2
        && v[0].nombre == "BTW+ION10+NOGRP+R.I.P.SCENE" && v[0].enlace == "/original/160075/72"
        && v[0].completa && v[0].paraSordos && v[0].descargas == 455
        && v[1].completa == false          // una traducción a medias no sirve
}

probar("el nombre de la serie va con mayúsculas en la URL") {
    Addic7ed.nombreEnURL("ted lasso") == "Ted_Lasso"
}

let capitulo = URL(fileURLWithPath: "/x/Ted.Lasso.S01E09.HDR.2160p.WEB-DL.DDP5.1.H.265-ROCCaT.mkv")
probar("nombre de la carpeta del capítulo") {
    Motor.carpetaDeCapitulo(para: capitulo) == "Ted Lasso S01E09"
        && Motor.carpetaDeCapitulo(para: URL(fileURLWithPath: "/x/The.Batman.2022.1080p.mkv")) == nil
}

probar("esSRT rechaza una página HTML con «-->» y acepta un .srt real") {
    let html = "\u{FEFF}<body>\r\n<!-- cupo diario -->\r\n<center>Has superado el límite de descargas</center></body>"
    let srt = (1...6).map { "\($0)\n00:00:0\($0),000 --> 00:00:0\($0),900\nHola \($0)\n" }.joined(separator: "\n")
    return !TextoSRT.esSRT(html) && TextoSRT.esSRT(srt) && !TextoSRT.esSRT("")
}

probar("organizar mete el capítulo y su .srt en su carpeta, y no toca a los demás") {
    let serie = temporal.appendingPathComponent("serie", isDirectory: true)
    try FileManager.default.createDirectory(at: serie, withIntermediateDirectories: true)
    let e1 = serie.appendingPathComponent("Show.Name.S02E01.WEB.mkv")
    let e2 = serie.appendingPathComponent("Show.Name.S02E02.WEB.mkv")
    for archivo in [e1, e2, Motor.destinoSRT(de: e1), Motor.destinoSRT(de: e2)] {
        try Data("x".utf8).write(to: archivo)
    }
    let nuevo = try Motor.organizarPorCapitulo(e1)
    let carpeta = serie.appendingPathComponent("Show Name S02E01")
    let gestor = FileManager.default
    let otraVez = try Motor.organizarPorCapitulo(nuevo)      // repetir no anida carpetas
    return otraVez == nuevo && nuevo == carpeta.appendingPathComponent(e1.lastPathComponent)
        && gestor.fileExists(atPath: nuevo.path)
        && gestor.fileExists(atPath: Motor.destinoSRT(de: nuevo).path)
        && !gestor.fileExists(atPath: e1.path)
        && gestor.fileExists(atPath: e2.path) && gestor.fileExists(atPath: Motor.destinoSRT(de: e2).path)
}

print("\n▸ Herramientas")

probar("encuentra ffmpeg y ffprobe") {
    Herramientas.faltantes.isEmpty
}

print("\n▸ Cola de la ventana")

// Un video de verdad, corto, para que el diagnóstico tenga algo que leer.
let videoDePrueba = temporal.appendingPathComponent("Prueba.Pelicula.2026.WEB-DL.mkv")
let subtituloFuente = temporal.appendingPathComponent("fuente.srt")
try? "1\n00:00:01,000 --> 00:00:02,000\n¿Dónde está la niña?\n"
    .write(to: subtituloFuente, atomically: true, encoding: .utf8)
// Las muestras se fabrican con el ffmpeg COMPLETO de Homebrew (el de la app no codifica).
if let fabrica = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first(where: FileManager.default.isExecutableFile) {
    let proceso = Process()
    proceso.executableURL = URL(fileURLWithPath: fabrica)
    proceso.arguments = [
        "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=160x120:rate=5:duration=2",
        "-i", subtituloFuente.path, "-map", "0:v", "-map", "1", "-c:v", "libx264",
        "-pix_fmt", "yuv420p", "-c:s", "srt", "-metadata:s:s:0", "language=spa", videoDePrueba.path,
    ]
    try? proceso.run()
    proceso.waitUntilExit()
}

// El fallo que esto vigila: cuando cada fila era un objeto observable aparte,
// la Cola no se enteraba de que habían terminado de analizarse y el botón
// Procesar se quedaba gris. La lista tiene que reflejarse en la cola.
let cola = await MainActor.run { Cola() }
await MainActor.run { cola.agregar([videoDePrueba]) }

var listas = false
for _ in 0..<50 {
    try? await Task.sleep(nanoseconds: 200_000_000)
    if await MainActor.run(body: { !cola.pendientes.isEmpty }) { listas = true; break }
}

await probarEsperando("la película entra en la cola") {
    await MainActor.run { cola.filas.count } == 1
}

await probarEsperando("al terminar el análisis la cola tiene pendientes (botón Procesar activo)") {
    listas
}

await probarEsperando("el diagnóstico llega a la fila") {
    await MainActor.run { cola.filas.first?.diagnostico?.elegida?.codec } == "subrip"
}

await probarEsperando("una película no se busca en Addic7ed aunque se prefiera latino") {
    guard let d = await MainActor.run(body: { cola.filas.first?.diagnostico }) else { return false }
    return !d.esEpisodio && !d.plan(preferirLatino: true).contains("Addic7ed")
}

await MainActor.run { cola.procesarTodo() }
for _ in 0..<50 {
    try? await Task.sleep(nanoseconds: 200_000_000)
    if await MainActor.run(body: { !cola.trabajando }) { break }
}

await probarEsperando("procesar deja el .srt junto al video") {
    let destino = Motor.destinoSRT(de: videoDePrueba)
    return FileManager.default.fileExists(atPath: destino.path) && TextoSRT.estaBienFormado(destino)
}

// Lo que pidió el usuario: si sólo hay español de España, avisar; y al soltar
// el latino bajado de Subdivx, que quede puesto.
await MainActor.run { cola.agregar([srtEspaña]) }
for _ in 0..<50 {
    try? await Task.sleep(nanoseconds: 100_000_000)
    if await MainActor.run(body: { cola.filas.first?.avisa == true }) { break }
}
await probarEsperando("soltar el de España deja la fila en aviso") {
    await MainActor.run { cola.filas.first?.avisa == true }
}

await MainActor.run { cola.agregar([zipBajado]) }
for _ in 0..<50 {
    try? await Task.sleep(nanoseconds: 100_000_000)
    if await MainActor.run(body: { cola.filas.first?.terminada == true }) { break }
}
await probarEsperando("soltar el .zip de Subdivx instala el latino y quita el aviso") {
    let bien = await MainActor.run { cola.filas.first?.terminada == true }
    let texto = (try? TextoSRT.leer(Motor.destinoSRT(de: videoDePrueba)).texto) ?? ""
    return bien && texto.contains("ustedes") && TextoSRT.estaBienFormado(Motor.destinoSRT(de: videoDePrueba))
}

print("\n▸ MKV limpio (remux)")

probar("los argumentos del remux: audios elegidos, sin subtítulos del original, .srt como español") {
    let args = Remux.argumentos(video: URL(fileURLWithPath: "/p/a.mkv"), subtitulo: URL(fileURLWithPath: "/p/a.srt"),
                                audios: [2, 5], salida: URL(fileURLWithPath: "/p/.a.parcial"))
    let texto = args.joined(separator: " ")
    return texto.contains("-map 0:v -map 0:2 -map 0:5 -map 1:0")
        && !texto.contains("0:s") && !texto.contains("-map 0 ")
        && texto.contains("language=spa") && texto.contains("-disposition:a:1 -default")
}

probar("el destino del remux no pisa el original") {
    Remux.destino(para: URL(fileURLWithPath: "/p/Peli.mkv")).lastPathComponent == "Peli (SubFix).mkv"
}

if let completo = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first(where: FileManager.default.isExecutableFile) {
    // Muestra: 1 video, audio inglés + italiano, y dos subtítulos que deben desaparecer.
    let carpetaMKV = temporal.appendingPathComponent("mkv")
    try! FileManager.default.createDirectory(at: carpetaMKV, withIntermediateDirectories: true)
    let pelicula = carpetaMKV.appendingPathComponent("Muestra.mkv")
    let viejo = carpetaMKV.appendingPathComponent("viejo.srt")
    let seis = { (linea: String) in (1...6).map { "\($0)\n00:00:0\($0 - 1),100 --> 00:00:0\($0 - 1),900\n\(linea)\n" }.joined(separator: "\n") }
    try! seis("Old sub").write(to: viejo, atomically: true, encoding: .utf8)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: completo)
    p.arguments = ["-nostdin", "-v", "error", "-y",
                   "-f", "lavfi", "-i", "color=c=black:s=64x64:d=1:r=10",
                   "-f", "lavfi", "-i", "sine=frequency=440:d=1",
                   "-f", "lavfi", "-i", "sine=frequency=880:d=1",
                   "-i", viejo.path, "-i", viejo.path,
                   "-map", "0", "-map", "1", "-map", "2", "-map", "3", "-map", "4",
                   "-c:v", "mpeg4", "-c:a", "aac", "-c:s", "srt",
                   "-metadata:s:a:0", "language=ita", "-metadata:s:a:1", "language=eng",
                   "-metadata:s:s:0", "language=eng", "-metadata:s:s:1", "language=fre", pelicula.path]
    p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()

    let nuevoSRT = Motor.destinoSRT(de: pelicula)
    try! TextoSRT.escribirParaElTV("1\n00:00:00,100 --> 00:00:00,900\n¿Dónde está la niña?\n", en: nuevoSRT)

    probar("remux: queda el inglés, se va el italiano y los subtítulos viejos, y entra el .srt en español") {
        let audios = try Sondeo.audios(de: pelicula)
        guard let ingles = audios.first(where: \.esIngles) else { return false }
        let hecho = try Remux.hacer(video: pelicula, subtitulo: nuevoSRT, audios: [ingles.indice])
        let a = try Sondeo.audios(de: hecho)
        let subs = try Sondeo.pistas(de: hecho)
        return a.count == 1 && a[0].idioma == "eng"
            && subs.count == 1 && subs[0].idioma == "spa" && subs[0].codec == "subrip"
            && FileManager.default.fileExists(atPath: pelicula.path)
    }

    probar("remux: si ya existe un MKV de una vez anterior, crea «(SubFix 2)» y no toca el otro") {
        let primero = carpetaMKV.appendingPathComponent("Muestra (SubFix).mkv")   // el de la prueba anterior
        guard FileManager.default.fileExists(atPath: primero.path) else { return false }
        let tamañoAntes = ((try FileManager.default.attributesOfItem(atPath: primero.path))[.size] as? Int) ?? -1
        let segundo = try Remux.hacer(video: pelicula, subtitulo: nuevoSRT, audios: [1])
        let tamañoDespues = ((try FileManager.default.attributesOfItem(atPath: primero.path))[.size] as? Int) ?? -2
        return segundo.lastPathComponent == "Muestra (SubFix 2).mkv" && tamañoAntes == tamañoDespues
    }

    probar("remux: las tildes del .srt sobreviven dentro del MKV") {
        let hecho = carpetaMKV.appendingPathComponent("Muestra (SubFix).mkv")
        let extraido = carpetaMKV.appendingPathComponent("sacado.srt")
        let subs = try Sondeo.pistas(de: hecho)
        try Sondeo.extraer(pista: subs[0], de: hecho, a: extraido)
        return try TextoSRT.leer(extraido).texto.contains("¿Dónde está la niña?")
    }

    probar("MKV sin extraer: el subtítulo sale de una pista y NO deja ningún .srt junto a la película") {
        let antes = Set(try FileManager.default.contentsOfDirectory(atPath: carpetaMKV.path))
        let pistas = try Sondeo.pistas(de: pelicula).filter(\.esTexto)
        guard let primera = pistas.first else { return false }
        let temporalSRT = try Remux.prepararSubtitulo(.pista(primera), para: pelicula)
        defer { try? FileManager.default.removeItem(at: temporalSRT) }
        let despues = Set(try FileManager.default.contentsOfDirectory(atPath: carpetaMKV.path))
        return antes == despues && TextoSRT.estaBienFormado(temporalSRT)
    }

    probar("MKV con subtítulo externo: acepta un .srt elegido a mano y lo limpia") {
        let externo = carpetaMKV.appendingPathComponent("bajado.srt")
        try seis("{\\an8}<i>Hola, ¿qué tal?</i>").write(to: externo, atomically: true, encoding: .utf8)
        let temporalSRT = try Remux.prepararSubtitulo(.archivo(externo), para: pelicula)
        defer { try? FileManager.default.removeItem(at: temporalSRT) }
        let texto = try TextoSRT.leer(temporalSRT).texto
        return texto.contains("Hola, ¿qué tal?") && !texto.contains("{\\an8}") && !texto.contains("<i>")
    }

    probar("MKV con subtítulo externo: rechaza algo que no es un .srt") {
        let basura = carpetaMKV.appendingPathComponent("basura.srt")
        try "<html><body>no soy un subtítulo</body></html>".write(to: basura, atomically: true, encoding: .utf8)
        do { _ = try Remux.prepararSubtitulo(.archivo(basura), para: pelicula); return false } catch { return true }
    }

    // Plan a medida: conservar una pista del archivo + añadir un .srt, y que «Procesar» lo cree.
    let bajado = carpetaMKV.appendingPathComponent("bajado.srt")
    let carpetaPlan = temporal.appendingPathComponent("plan")
    try! FileManager.default.createDirectory(at: carpetaPlan, withIntermediateDirectories: true)
    let peliPlan = carpetaPlan.appendingPathComponent("PeliPlan.mkv")
    try! FileManager.default.copyItem(at: pelicula, to: peliPlan)

    probar("plan: conserva una pista del archivo, añade un .srt (español, por defecto) y quita el resto") {
        let audios = try Sondeo.audios(de: peliPlan)
        let subs = try Sondeo.pistas(de: peliPlan)
        guard let ingles = audios.first(where: \.esIngles),
              let inglesSub = subs.first(where: { $0.idioma == "eng" }) else { return false }
        let plan = PlanDeMKV(audios: [ingles.indice], subtitulosDelArchivo: [inglesSub], añadidos: [bajado])
        let hecho = try Remux.hacer(video: peliPlan, plan: plan)
        let sal = try Sondeo.pistas(de: hecho)
        let salidaJSON = try Herramientas.correr("ffprobe", ["-v", "error", "-select_streams", "s",
            "-show_entries", "stream=index:stream_disposition=default", "-of", "csv=p=0", hecho.path]).texto
        return sal.count == 2 && sal[0].idioma == "eng" && sal[1].idioma == "spa"
            && salidaJSON.contains(",1") && salidaJSON.components(separatedBy: ",1").count == 2
            && plan.resumen.contains("1 añadido")
    }

    probar("nombre del archivo: se limpia lo peligroso y vacío vale como «el de siempre»") {
        Remux.nombreLimpio(" Mi/Peli:2.mkv ") == "Mi-Peli-2" && Remux.nombreLimpio(".oculta") == "oculta"
            && Remux.nombreLimpio("   ") == nil && Remux.nombreLimpio(nil) == nil
            && Remux.nombreLimpio("Peli.MKV") == "Peli"
    }

    probar("idiomas: los argumentos rotulan audio y subtítulos; «Sin idioma» quita el título") {
        let vid = URL(fileURLWithPath: "/p/a.mkv"), srt = URL(fileURLWithPath: "/p/a.srt")
        let plan = PlanDeMKV(audios: [1], subtitulosDelArchivo: [], añadidos: [srt],
                             idiomasDeAudio: [1: Idioma.lista.first { $0.nombre == "Italiano" }!],
                             idiomasDeAñadidos: [srt: Idioma.lista.first { $0.nombre == "Español (Latinoamérica)" }!])
        let t = Remux.argumentos(video: vid, plan: plan, preparados: [srt], salida: URL(fileURLWithPath: "/p/o")).joined(separator: "|")
        var plan2 = plan
        plan2.idiomasDeAudio = [1: .sinIdioma]
        let t2 = Remux.argumentos(video: vid, plan: plan2, preparados: [srt], salida: URL(fileURLWithPath: "/p/o")).joined(separator: "|")
        return t.contains("-metadata:s:a:0|language=ita|-metadata:s:a:0|title=Italiano")
            && t.contains("-metadata:s:s:0|language=spa|-metadata:s:s:0|title=Español (Latinoamérica)")
            && t2.contains("language=und|-metadata:s:a:0|title=|")
    }

    probar("nombre e idiomas elegidos: el MKV sale con ese nombre y esos rótulos; el segundo se numera") {
        let plan = PlanDeMKV(audios: [try Sondeo.audios(de: peliPlan).first(where: \.esIngles)!.indice],
                             subtitulosDelArchivo: [], añadidos: [bajado], nombre: "Mi Película Editada",
                             idiomasDeAudio: [try Sondeo.audios(de: peliPlan).first(where: \.esIngles)!.indice:
                                                Idioma.lista.first { $0.nombre == "Français" }!],
                             idiomasDeAñadidos: [bajado: Idioma.lista.first { $0.nombre == "Español (España)" }!])
        let uno = try Remux.hacer(video: peliPlan, plan: plan)
        let dos = try Remux.hacer(video: peliPlan, plan: plan)
        let etiquetas = try Herramientas.correr("ffprobe", ["-v", "error", "-show_entries",
            "stream=codec_type:stream_tags=language,title", "-of", "csv=p=0", uno.path]).texto
        return uno.lastPathComponent == "Mi Película Editada.mkv" && dos.lastPathComponent == "Mi Película Editada (2).mkv"
            && etiquetas.contains("fre,Français") && etiquetas.contains("spa,Español (España)")
    }

    probar("progreso: crece sin retroceder, queda dentro de 0…1 y termina en 1") {
        final class Registro: @unchecked Sendable {
            private let candado = NSLock(); private var valores: [Double] = []
            func añadir(_ v: Double) { candado.lock(); valores.append(v); candado.unlock() }
            var todos: [Double] { candado.lock(); defer { candado.unlock() }; return valores }
        }
        let registro = Registro()
        let audios = try Sondeo.audios(de: peliPlan)
        let plan = PlanDeMKV(audios: [audios.first!.indice], subtitulosDelArchivo: [], añadidos: [bajado],
                             nombre: "Con progreso")
        _ = try Remux.hacer(video: peliPlan, plan: plan) { registro.añadir($0) }
        let v = registro.todos
        return v.first == 0 && v.last == 1 && v.allSatisfy { $0 >= 0 && $0 <= 1 }
            && zip(v, v.dropFirst()).allSatisfy { $0 <= $1 }
    }

    probar("plan: un subtítulo mov_text de un MP4 se convierte a SRT dentro del MKV") {
        let mp4 = carpetaPlan.appendingPathComponent("Movil.mp4")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: completo)
        p.arguments = ["-nostdin", "-v", "error", "-y",
                       "-f", "lavfi", "-i", "color=c=black:s=64x64:d=1:r=10",
                       "-f", "lavfi", "-i", "sine=d=1", "-i", viejo.path,
                       "-map", "0", "-map", "1", "-map", "2", "-c:v", "mpeg4", "-c:a", "aac", "-c:s", "mov_text",
                       "-metadata:s:s:0", "language=spa", mp4.path]
        p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        let audios = try Sondeo.audios(de: mp4)
        let subs = try Sondeo.pistas(de: mp4)
        guard subs.first?.codec == "mov_text", let a = audios.first else { return false }
        let hecho = try Remux.hacer(video: mp4, plan: PlanDeMKV(audios: [a.indice], subtitulosDelArchivo: subs, añadidos: []))
        let sal = try Sondeo.pistas(de: hecho)
        return sal.count == 1 && sal[0].codec == "subrip"
    }

    let colaPlan = await MainActor.run { Cola() }
    let peliCola = carpetaPlan.appendingPathComponent("PeliCola.mkv")
    try! FileManager.default.copyItem(at: pelicula, to: peliCola)
    await MainActor.run { colaPlan.agregar([peliCola]) }
    for _ in 0..<50 {
        try? await Task.sleep(nanoseconds: 100_000_000)
        if await MainActor.run(body: { colaPlan.pendientes.count == 1 }) { break }
    }
    let idCola = await MainActor.run { colaPlan.filas.first!.id }
    let audiosCola = try! Sondeo.audios(de: peliCola)
    await MainActor.run {
        colaPlan.guardarPlan(idCola, PlanDeMKV(audios: [audiosCola.first(where: \.esIngles)!.indice],
                                               subtitulosDelArchivo: [], añadidos: [bajado]))
        colaPlan.procesarTodo()
    }
    for _ in 0..<100 {
        try? await Task.sleep(nanoseconds: 100_000_000)
        if await MainActor.run(body: { colaPlan.filas.first?.terminada == true }) { break }
    }
    await probarEsperando("Procesar con plan crea el MKV a medida y NO extrae el .srt") {
        let hecho = carpetaPlan.appendingPathComponent("PeliCola (SubFix).mkv")
        let hayMKV = FileManager.default.fileExists(atPath: hecho.path)
        let haySRT = FileManager.default.fileExists(atPath: Motor.destinoSRT(de: peliCola).path)
        let subs = (try? Sondeo.pistas(de: hecho)) ?? []
        let terminada = await MainActor.run { colaPlan.filas.first?.terminada == true }
        return hayMKV && !haySRT && terminada && subs.count == 1 && subs[0].idioma == "spa"
            && FileManager.default.fileExists(atPath: peliCola.path)
    }

    // Regresión (6-oct): el ffmpeg mínimo sin decodificadores de video reescribía mal las marcas
    // de tiempo al copiar video con fotogramas B y la película salía a tirones. Se prueba con
    // el binario del PROYECTO, no con el de Homebrew, que no tenía el problema.
    let propio = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/bin/ffmpeg").path
    if FileManager.default.isExecutableFile(atPath: propio) {
        probar("el ffmpeg del bundle conserva las marcas de tiempo del video con fotogramas B") {
            let origen = carpetaPlan.appendingPathComponent("conB.mkv")
            let copia = carpetaPlan.appendingPathComponent("conB-copia.mkv")
            let crear = Process()
            crear.executableURL = URL(fileURLWithPath: completo)
            crear.arguments = ["-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=s=320x180:d=4:r=24",
                               "-c:v", "libx265", "-preset", "ultrafast", origen.path]
            try crear.run(); crear.waitUntilExit()
            let copiar = Process()
            copiar.executableURL = URL(fileURLWithPath: propio)
            copiar.arguments = ["-nostdin", "-v", "error", "-y", "-i", origen.path, "-c", "copy", "-f", "matroska", copia.path]
            try copiar.run(); copiar.waitUntilExit()
            func tiempos(_ url: URL) throws -> String {
                try Herramientas.correr("ffprobe", ["-v", "error", "-select_streams", "v:0",
                    "-show_entries", "packet=pts,duration", "-of", "csv=p=0", url.path]).texto
            }
            let antes = try tiempos(origen)
            let despues = try tiempos(copia)
            return !antes.isEmpty && antes == despues
        }
    }
} else {
    print("  ⏭  sin ffmpeg completo de Homebrew: se omiten las pruebas con archivo real")
}

print("\n\(pasadas) pasadas, \(falladas) falladas\n")
exit(falladas == 0 ? 0 : 1)
