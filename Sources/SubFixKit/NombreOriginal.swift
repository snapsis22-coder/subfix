import Foundation

/// Guarda el nombre con el que se bajó un video («Tony.2026.2160p.AMZN.WEB-DL…mkv»)
/// cuando Organizar lo deja como «Tony (2026).mkv», en dos sitios:
///
/// 1. **macOS** — en «Dónde se obtuvo» (Obtener información). Instantáneo y vale para
///    cualquier formato, pero se pierde al copiar a un disco exFAT o por la red.
/// 2. **Dentro del MKV** — una etiqueta `NOMBRE_ORIGINAL` que viaja con el archivo.
///    Va aparte del título a propósito: el título lo enseñan el TV y Jellyfin.
///
/// La etiqueta se escribe como «Latino por defecto»: sin reescribir el archivo, en un
/// relleno (Void) que mkvmerge deja al inicio. Si no hay relleno que alcance, no se
/// toca el archivo (reescribir 13 GB no compensa) y queda sólo lo de macOS.
public enum NombreOriginal {

    public static let etiqueta = "NOMBRE_ORIGINAL"

    public struct Resultado: Equatable, Sendable {
        public var enMacOS = false
        /// nil = se escribió o ya estaba; un texto = por qué no se pudo.
        public var problemaEnMKV: String?
    }

    /// Los dos a la vez. Nunca lanza: lo que no se pudo queda dicho en el resultado.
    public static func guardar(_ nombre: String, en video: URL) -> Resultado {
        var resultado = Resultado()
        resultado.enMacOS = (try? guardarEnMacOS(nombre, en: video)) != nil
        if ["mkv", "webm"].contains(video.pathExtension.lowercased()) {
            do { _ = try guardarEnMKV(nombre, en: video) } catch {
                resultado.problemaEnMKV = (error as? CabeceraMKV.Fallo)?.detalle ?? error.localizedDescription
            }
        } else {
            resultado.problemaEnMKV = "no es MKV"
        }
        return resultado
    }

    // MARK: - macOS («Dónde se obtuvo»)

    static let atributo = "com.apple.metadata:kMDItemWhereFroms"

    /// Se agrega a lo que ya hubiera (el navegador a veces deja ahí la dirección de descarga).
    public static func guardarEnMacOS(_ nombre: String, en video: URL) throws {
        var lista = leerDeMacOS(video)
        guard !lista.contains(nombre) else { return }
        lista.append(nombre)
        let datos = try PropertyListSerialization.data(fromPropertyList: lista, format: .binary, options: 0)
        let hecho = datos.withUnsafeBytes { bytes in
            setxattr(video.path, atributo, bytes.baseAddress, datos.count, 0, 0)
        }
        guard hecho == 0 else { throw CabeceraMKV.Fallo(detalle: String(cString: strerror(errno))) }
    }

    public static func leerDeMacOS(_ video: URL) -> [String] {
        let largo = getxattr(video.path, atributo, nil, 0, 0, 0)
        guard largo > 0 else { return [] }
        var datos = Data(count: largo)
        let leido = datos.withUnsafeMutableBytes { getxattr(video.path, atributo, $0.baseAddress, largo, 0, 0) }
        guard leido == largo else { return [] }
        return (try? PropertyListSerialization.propertyList(from: datos, format: nil)) as? [String] ?? []
    }

    // MARK: - Dentro del MKV

    static let idEtiquetas: UInt32 = 0x1254_C367, idEtiqueta: UInt32 = 0x7373, idObjetivos: UInt32 = 0x63C0
    static let idSimple: UInt32 = 0x67C8, idNombre: UInt32 = 0x45A3, idTexto: UInt32 = 0x4487

    /// Lo que ffprobe lee como etiqueta del archivo, o nil.
    public static func leerDeMKV(_ video: URL) -> String? {
        guard let salida = try? Herramientas.correr("ffprobe", [
            "-v", "error", "-show_entries", "format_tags=\(etiqueta)", "-of", "default=nw=1:nk=1", video.path,
        ]), salida.codigo == 0 else { return nil }
        let texto = salida.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return texto.isEmpty ? nil : texto
    }

    /// Escribe la etiqueta. Devuelve `false` si ya estaba con ese nombre.
    @discardableResult
    public static func guardarEnMKV(_ nombre: String, en video: URL) throws -> Bool {
        if leerDeMKV(video) == nombre { return false }
        let manejador = try FileHandle(forReadingFrom: video)
        let cabeza = [UInt8](try manejador.read(upToCount: 8 << 20) ?? Data())
        try manejador.close()

        let nuevo = try etiquetas(nombre)
        guard let vacio = try rellenoQueAlcance(cabeza, para: nuevo.count) else {
            throw CabeceraMKV.Fallo(detalle: "no hay espacio libre al inicio del MKV (haría falta reescribirlo)")
        }
        var tramo = nuevo
        let sobra = vacio.fin - vacio.inicio - nuevo.count
        if sobra > 0 {
            guard let relleno = CabeceraMKV.rellenoDe(sobra, largo: vacio.largoTamaño) else {
                throw CabeceraMKV.Fallo(detalle: "el espacio libre no cuadra")
            }
            tramo += relleno
        }
        let antes = [UInt8](cabeza[vacio.inicio..<vacio.fin])
        precondition(antes.count == tramo.count)
        let copia = try CabeceraMKV.guardarCopia(antes, de: video, desde: vacio.inicio)
        try CabeceraMKV.escribir(tramo, en: video, desde: vacio.inicio)

        guard leerDeMKV(video) == nombre else {
            try CabeceraMKV.escribir(antes, en: video, desde: vacio.inicio)
            throw CabeceraMKV.Fallo(detalle: "al releerlo no quedó; se dejó como estaba (copia en \(copia.lastPathComponent))")
        }
        return true
    }

    /// `Tags › Tag › (Targets vacío = todo el archivo) + SimpleTag › NOMBRE_ORIGINAL = nombre`.
    static func etiquetas(_ nombre: String) throws -> [UInt8] {
        func elemento(_ id: UInt32, _ datos: [UInt8]) throws -> [UInt8] {
            let bytesId = (0..<4).reversed().map { UInt8(truncatingIfNeeded: id >> (8 * $0)) }.drop { $0 == 0 }
            return Array(bytesId) + (try CabeceraMKV.tamaño(datos.count, largo: 1)) + datos
        }
        let simple = try elemento(idSimple, try elemento(idNombre, Array(etiqueta.utf8))
                                  + elemento(idTexto, Array(nombre.utf8)))
        return try elemento(idEtiquetas, try elemento(idEtiqueta, try elemento(idObjetivos, []) + simple))
    }

    /// Un relleno de primer nivel, antes del primer Cluster, donde quepa `largo` (y lo
    /// que sobre pueda quedar como relleno). Se prefiere uno que NO esté pegado a la
    /// cabecera de pistas: ese lo necesita «Latino por defecto».
    static func rellenoQueAlcance(_ b: [UInt8], para largo: Int) throws -> CabeceraMKV.Elemento? {
        guard let ebml = CabeceraMKV.elemento(b, 0, limite: b.count), ebml.id == 0x1A45_DFA3,
              let segmento = CabeceraMKV.elemento(b, ebml.fin, limite: b.count),
              segmento.id == CabeceraMKV.idSegmento else {
            throw CabeceraMKV.Fallo(detalle: "no parece un MKV")
        }
        var p = segmento.datos, anterior: UInt32 = 0
        let fin = min(segmento.fin, b.count)
        var candidatos: [(CabeceraMKV.Elemento, trasPistas: Bool)] = []
        while p < fin, let e = CabeceraMKV.elemento(b, p, limite: fin), e.fin <= b.count {
            if e.id == CabeceraMKV.idCluster { break }
            if e.id == CabeceraMKV.idVacio {
                let total = e.fin - e.inicio
                if total == largo || total - largo >= 2 { candidatos.append((e, anterior == CabeceraMKV.idPistas)) }
            }
            anterior = e.id
            p = e.fin
        }
        return (candidatos.first { !$0.trasPistas } ?? candidatos.first)?.0
    }
}
