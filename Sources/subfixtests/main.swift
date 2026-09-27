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
_ = try? Herramientas.correr("ffmpeg", [
    "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=160x120:rate=5:duration=2",
    "-i", subtituloFuente.path, "-map", "0:v", "-map", "1", "-c:v", "libx264",
    "-pix_fmt", "yuv420p", "-c:s", "srt", "-metadata:s:s:0", "language=spa", videoDePrueba.path,
])

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

print("\n\(pasadas) pasadas, \(falladas) falladas\n")
exit(falladas == 0 ? 0 : 1)
