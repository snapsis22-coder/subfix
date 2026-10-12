import Foundation

/// Cambia qué pistas salen solas en un MKV **sin reescribir el archivo**, como
/// `mkvpropedit`: sólo toca la cabecera de pistas (unos pocos KB al inicio).
///
/// La marca «por defecto» (FlagDefault) es un byte dentro de cada pista. Si ya está
/// escrita, se cambia su valor y nada se mueve. Si falta (vale 1 cuando falta, y
/// mkvmerge la omite justo en la pista por defecto), hay que añadir 3 bytes: se sacan
/// del relleno vacío (Void) que mkvmerge deja después de la cabecera, así que todo lo
/// que viene detrás —capítulos, video, índices— queda en el mismo sitio.
///
/// Antes de escribir guarda una copia de los bytes originales en
/// `~/Library/Application Support/SubFix/Cabeceras` y, si al releer con ffprobe no
/// quedó lo pedido, los vuelve a poner.
public enum CabeceraMKV {

    public struct Fallo: LocalizedError {
        public let detalle: String
        public var errorDescription: String? { "No se pudo cambiar la cabecera: \(detalle)" }
    }

    public enum Resultado: Equatable, Sendable {
        /// Se cambió el archivo; el texto dice qué quedó automático.
        case cambiado(String)
        /// Lo latino ya era lo automático.
        case yaEstaba(String)
        /// El archivo no trae ni subtítulo ni audio latino.
        case sinLatino
    }

    /// El botón «Latino por defecto»: el subtítulo latino queda como el único automático
    /// y, sólo si el archivo trae doblaje latino, también el audio. Lo demás no se toca.
    public static func latinoPorDefecto(_ video: URL) throws -> Resultado {
        guard ["mkv", "webm"].contains(video.pathExtension.lowercased()) else {
            throw Fallo(detalle: "sólo se puede en archivos .mkv sin crear otro")
        }
        let subtitulos = try Sondeo.pistas(de: video)
        let audios = try Sondeo.audios(de: video)
        let subLatino = subtitulos.filter { $0.esLatino && !$0.forzada && !$0.descartable }
            .max { $0.puntaje < $1.puntaje }
        let audioLatino = audios.first(where: \.esLatino)
        guard subLatino != nil || audioLatino != nil else { return .sinLatino }

        var deseado: [Int: Bool] = [:]
        if let subLatino { for s in subtitulos { deseado[s.indice] = s.indice == subLatino.indice } }
        if let audioLatino { for a in audios { deseado[a.indice] = a.indice == audioLatino.indice } }
        let queda = [subLatino.map { _ in "subtítulo" }, audioLatino.map { _ in "audio" }]
            .compactMap { $0 }.joined(separator: " y ") + " latino"

        guard try marcar(deseado, en: video, tipos: Dictionary(uniqueKeysWithValues:
            subtitulos.map { ($0.indice, tipoSubtitulo) } + audios.map { ($0.indice, tipoAudio) })) else {
            return .yaEstaba("ya tenía el \(queda) por defecto")
        }
        return .cambiado("\(queda) por defecto")
    }

    // MARK: - Escritura

    static let idSegmento: UInt32 = 0x1853_8067, idPistas: UInt32 = 0x1654_AE6B, idCluster: UInt32 = 0x1F43_B675
    static let idPista: UInt32 = 0xAE, idTipo: UInt32 = 0x83, idPorDefecto: UInt32 = 0x88
    static let idVacio: UInt32 = 0xEC, idCRC: UInt32 = 0xBF
    static let tipoAudio = 2, tipoSubtitulo = 17

    /// Deja cada pista (por su índice, el mismo de ffprobe) con la marca pedida.
    /// `tipos` sirve de control: el orden de la cabecera tiene que casar con ffprobe.
    /// Devuelve `false` si ya estaban así (no escribe nada).
    @discardableResult
    public static func marcar(_ deseado: [Int: Bool], en video: URL, tipos: [Int: Int] = [:]) throws -> Bool {
        let manejador = try FileHandle(forReadingFrom: video)
        let cabeza = [UInt8](try manejador.read(upToCount: 8 << 20) ?? Data())
        try manejador.close()

        let (pistas, siguiente) = try ubicarPistas(cabeza)
        var entradas = try elementos(cabeza, desde: pistas.datos, hasta: pistas.fin)
        // ffmpeg (y los MKV que crea SubFix) ponen una suma CRC-32 de primera: se recalcula al final.
        let conCRC = entradas.first?.id == idCRC
        if conCRC { entradas.removeFirst() }
        guard !entradas.contains(where: { $0.id == idCRC }) else { throw Fallo(detalle: "la cabecera trae una suma CRC rara") }

        var contenido: [UInt8] = []
        var orden = 0, cambia = false
        for entrada in entradas {
            guard entrada.id == idPista else { contenido += cabeza[entrada.inicio..<entrada.fin]; continue }
            defer { orden += 1 }
            let hijos = try elementos(cabeza, desde: entrada.datos, hasta: entrada.fin)
            guard !hijos.contains(where: { $0.id == idCRC }) else { throw Fallo(detalle: "la pista trae suma CRC") }
            guard let quiero = deseado[orden] else { contenido += cabeza[entrada.inicio..<entrada.fin]; continue }

            if let tipo = tipos[orden], let tipoReal = hijos.first(where: { $0.id == idTipo }).map({ entero(cabeza, $0) }),
               tipoReal != tipo {
                throw Fallo(detalle: "el orden de las pistas no casa con lo que leyó ffprobe")
            }
            var nuevo: [UInt8] = []
            var tenia = false
            for hijo in hijos {
                if hijo.id == idPorDefecto, hijo.tamaño >= 1 {
                    tenia = true
                    if (entero(cabeza, hijo) != 0) != quiero { cambia = true }
                    nuevo += cabeza[hijo.inicio..<hijo.datos]                         // mismo id y tamaño
                    nuevo += [UInt8](repeating: 0, count: hijo.tamaño - 1) + [quiero ? 1 : 0]
                } else {
                    nuevo += cabeza[hijo.inicio..<hijo.fin]
                }
            }
            if !tenia, !quiero {                     // faltaba = 1: hay que escribir el 0
                nuevo += [0x88, 0x81, 0x00]
                cambia = true
            }
            contenido += cabeza[entrada.inicio..<(entrada.inicio + entrada.largoId)]
            contenido += try tamaño(nuevo.count, largo: entrada.largoTamaño) + nuevo
        }
        guard orden > (deseado.keys.max() ?? -1) else { throw Fallo(detalle: "faltan pistas en la cabecera") }
        guard cambia else { return false }

        if conCRC {
            let suma = crc32(contenido)
            contenido = [0xBF, 0x84] + (0..<4).map { UInt8(truncatingIfNeeded: suma >> (8 * $0)) } + contenido
        }
        var tramo = [UInt8](cabeza[pistas.inicio..<(pistas.inicio + pistas.largoId)])
        tramo += try tamaño(contenido.count, largo: pistas.largoTamaño) + contenido
        let original = [UInt8](cabeza[pistas.inicio..<pistas.fin])
        var fin = pistas.fin

        if tramo.count > original.count {
            // Lo que crece sale del relleno que sigue a la cabecera.
            guard let vacio = siguiente, vacio.id == idVacio else {
                throw Fallo(detalle: "no hay espacio libre junto a la cabecera (haría falta reescribir el archivo)")
            }
            let disponible = vacio.fin - vacio.inicio - (tramo.count - original.count)
            guard let relleno = rellenoDe(disponible, largo: vacio.largoTamaño) else {
                throw Fallo(detalle: "no alcanza el espacio libre junto a la cabecera")
            }
            tramo += relleno
            fin = vacio.fin
        } else if tramo.count < original.count {
            throw Fallo(detalle: "la cabecera nueva quedó más corta (no debería pasar)")
        }

        let antes = [UInt8](cabeza[pistas.inicio..<fin])
        precondition(antes.count == tramo.count)
        let copia = try guardarCopia(antes, de: video, desde: pistas.inicio)
        try escribir(tramo, en: video, desde: pistas.inicio)

        // Se comprueba leyendo de nuevo, como lo leerá un reproductor.
        let leido = (try? Sondeo.pistas(de: video).map { ($0.indice, $0.porDefecto) }
                     + Sondeo.audios(de: video).map { ($0.indice, $0.porDefecto) }) ?? []
        let marcas = Dictionary(leido, uniquingKeysWith: { a, _ in a })
        guard deseado.allSatisfy({ marcas[$0.key] == $0.value }) else {
            try escribir(antes, en: video, desde: pistas.inicio)
            throw Fallo(detalle: "al releerlo no quedó bien; se dejó como estaba (copia en \(copia.lastPathComponent))")
        }
        return true
    }

    private static func escribir(_ bytes: [UInt8], en video: URL, desde posicion: Int) throws {
        let manejador = try FileHandle(forUpdating: video)
        defer { try? manejador.close() }
        try manejador.seek(toOffset: UInt64(posicion))
        try manejador.write(contentsOf: Data(bytes))
        try manejador.synchronize()
    }

    /// Dónde quedan las copias de las cabeceras; las pruebas la cambian por una temporal.
    nonisolated(unsafe) public static var carpetaDeCopias = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SubFix/Cabeceras")

    /// Los bytes que se van a cambiar, para poder volver atrás a mano.
    private static func guardarCopia(_ bytes: [UInt8], de video: URL, desde posicion: Int) throws -> URL {
        let carpeta = carpetaDeCopias
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let fecha = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let copia = carpeta.appendingPathComponent("\(video.lastPathComponent) · \(fecha) · desde el byte \(posicion).bin")
        try Data(bytes).write(to: copia)
        return copia
    }

    // MARK: - Lectura de EBML (el formato de los MKV)

    struct Elemento {
        let id: UInt32
        let inicio: Int, datos: Int, tamaño: Int
        let largoId: Int, largoTamaño: Int
        var fin: Int { datos + tamaño }
    }

    /// Un número de largo variable: el primer bit en 1 dice cuántos bytes ocupa.
    static func vint(_ b: [UInt8], _ p: Int, conMarca: Bool) -> (valor: UInt64, largo: Int, desconocido: Bool)? {
        guard p < b.count, b[p] != 0 else { return nil }
        let largo = b[p].leadingZeroBitCount + 1
        guard largo <= 8, p + largo <= b.count else { return nil }
        var valor = UInt64(conMarca ? b[p] : b[p] & (0xFF >> largo))
        for i in 1..<largo { valor = valor << 8 | UInt64(b[p + i]) }
        let todoUnos = !conMarca && valor == (UInt64(1) << (7 * largo)) - 1
        return (valor, largo, todoUnos)
    }

    static func elemento(_ b: [UInt8], _ p: Int, limite: Int) -> Elemento? {
        guard let id = vint(b, p, conMarca: true), id.largo <= 4,
              let tam = vint(b, p + id.largo, conMarca: false) else { return nil }
        let datos = p + id.largo + tam.largo
        let tamaño = tam.desconocido ? limite - datos : Int(tam.valor)
        return Elemento(id: UInt32(id.valor), inicio: p, datos: datos, tamaño: tamaño,
                        largoId: id.largo, largoTamaño: tam.largo)
    }

    static func elementos(_ b: [UInt8], desde: Int, hasta: Int) throws -> [Elemento] {
        var lista: [Elemento] = [], p = desde
        while p < hasta {
            guard let e = elemento(b, p, limite: hasta), e.fin <= hasta else {
                throw Fallo(detalle: "la cabecera está dañada o no se entiende")
            }
            lista.append(e)
            p = e.fin
        }
        return lista
    }

    /// La cabecera de pistas y lo que la sigue (el relleno, si lo hay).
    static func ubicarPistas(_ b: [UInt8]) throws -> (Elemento, Elemento?) {
        guard let ebml = elemento(b, 0, limite: b.count), ebml.id == 0x1A45_DFA3,
              let segmento = elemento(b, ebml.fin, limite: b.count), segmento.id == idSegmento else {
            throw Fallo(detalle: "no parece un MKV")
        }
        var p = segmento.datos
        let fin = min(segmento.fin, b.count)
        while p < fin, let e = elemento(b, p, limite: fin) {
            if e.id == idCluster { break }
            if e.id == idPistas {
                guard e.fin <= b.count else { throw Fallo(detalle: "la cabecera de pistas es demasiado grande") }
                return (e, elemento(b, e.fin, limite: fin))
            }
            p = e.fin
        }
        throw Fallo(detalle: "no encontré la cabecera de pistas al inicio del archivo")
    }

    static func entero(_ b: [UInt8], _ e: Elemento) -> Int {
        b[e.datos..<e.fin].reduce(0) { $0 << 8 | Int($1) }
    }

    /// Un tamaño escrito con `largo` bytes (como estaba), o con más si no cabe.
    static func tamaño(_ n: Int, largo: Int) throws -> [UInt8] {
        for l in largo...8 where n < (1 << (7 * l)) - 1 {
            let valor = UInt64(1) << (7 * l) | UInt64(n)
            return (0..<l).reversed().map { UInt8(truncatingIfNeeded: valor >> (8 * $0)) }
        }
        throw Fallo(detalle: "tamaño imposible")
    }

    /// CRC-32 (el de zip), que Matroska guarda con el byte menos significativo primero.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    /// Un relleno (Void) que ocupe exactamente `total` bytes, o nil si no cabe ninguno.
    static func rellenoDe(_ total: Int, largo: Int) -> [UInt8]? {
        for l in stride(from: max(largo, 1), through: 1, by: -1) {
            let datos = total - 1 - l
            guard datos >= 0, datos < (1 << (7 * l)) - 1, let t = try? tamaño(datos, largo: l), t.count == l else { continue }
            return [0xEC] + t + [UInt8](repeating: 0, count: datos)
        }
        return nil
    }
}
