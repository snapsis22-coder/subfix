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

await MainActor.run { cola.procesarTodo() }
for _ in 0..<50 {
    try? await Task.sleep(nanoseconds: 200_000_000)
    if await MainActor.run(body: { !cola.trabajando }) { break }
}

await probarEsperando("procesar deja el .srt junto al video") {
    let destino = Motor.destinoSRT(de: videoDePrueba)
    return FileManager.default.fileExists(atPath: destino.path) && TextoSRT.estaBienFormado(destino)
}

print("\n\(pasadas) pasadas, \(falladas) falladas\n")
exit(falladas == 0 ? 0 : 1)
