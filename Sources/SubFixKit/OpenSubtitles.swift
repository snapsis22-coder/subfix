import Compression
import Foundation

/// Búsqueda de subtítulos en OpenSubtitles.
///
/// Se usa el endpoint viejo `rest.opensubtitles.org`, que sigue vivo y **no pide
/// API key** — sólo un User-Agent. La API v1 nueva responde 403 sin credenciales.
public enum OpenSubtitles {

    static let base = "https://rest.opensubtitles.org/search"
    static let agente = "SubDB/1.0"

    public struct Hallazgo {
        public let texto: String
        public let nombreDelArchivo: String
        /// Encontrado por hash del archivo: es el mismo release, va sincronizado.
        public let porHash: Bool

        public var explicacion: String {
            porHash
                ? "OpenSubtitles, por hash exacto del archivo"
                : "OpenSubtitles, por título — conviene revisar la sincronía"
        }
    }

    // MARK: - Hash

    /// Hash de OpenSubtitles: tamaño del archivo más los primeros y últimos
    /// 64 KB, sumados como enteros de 64 bits. Identifica el release exacto.
    public static func hash(de url: URL) throws -> String? {
        let trozo = 65536
        let manejador = try FileHandle(forReadingFrom: url)
        defer { try? manejador.close() }

        let tamaño = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard tamaño >= trozo * 2 else { return nil }

        var suma = UInt64(tamaño)
        func sumar(_ datos: Data) {
            datos.withUnsafeBytes { crudo in
                let enteros = crudo.bindMemory(to: UInt64.self)
                for valor in enteros { suma = suma &+ UInt64(littleEndian: valor) }
            }
        }
        sumar(manejador.readData(ofLength: trozo))
        try manejador.seek(toOffset: UInt64(tamaño - trozo))
        sumar(manejador.readData(ofLength: trozo))

        return String(format: "%016qx", suma)
    }

    // MARK: - Nombre del release

    /// «The.Batman.2022.1080p.WEB-DL-NTb.mkv» → («the batman», nil, nil)
    static let ruido = "\\b(1080p|720p|2160p|480p|4k|web-?dl|web-?rip|bluray|brrip|bdrip|hdrip|dvdrip|"
                     + "hdtv|remux|x264|x265|h\\.?264|h\\.?265|hevc|10bit|hdr|dv|dolby|ddp?5\\.1|aac|"
                     + "atmos|truehd|dts|amzn|nf|hmax|dsnp|proper|repack|extended|internal)\\b.*"

    public static func tituloLimpio(_ url: URL) -> (titulo: String, temporada: Int?, episodio: Int?) {
        var nombre = url.deletingPathExtension().lastPathComponent
        var temporada: Int?, episodio: Int?

        if let coincidencia = nombre.range(of: "[.\\s_-][Ss](\\d{1,2})[\\s._-]?[Ee](\\d{1,3})",
                                           options: .regularExpression) {
            let marca = String(nombre[coincidencia])
            let numeros = marca.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { !$0.isEmpty }
            if numeros.count >= 2 { temporada = Int(numeros[0]); episodio = Int(numeros[1]) }
            nombre = String(nombre[nombre.startIndex..<coincidencia.lowerBound])
        }
        nombre = nombre.replacingOccurrences(of: ruido, with: "",
                                             options: [.regularExpression, .caseInsensitive])
        nombre = nombre.replacingOccurrences(of: "\\b(19|20)\\d{2}\\b.*", with: "",
                                             options: .regularExpression)
        nombre = nombre.replacingOccurrences(of: "[._+\\[\\]()-]+", with: " ", options: .regularExpression)
        return (nombre.trimmingCharacters(in: .whitespaces).lowercased(), temporada, episodio)
    }

    // MARK: - Búsqueda

    private struct Resultado: Decodable {
        let SubFileName: String?
        let SubFormat: String?
        let SubDownloadsCnt: String?
        let SubDownloadLink: String?
        let SubBad: String?
        let MatchedBy: String?
    }

    public static func buscar(para video: URL) async -> Hallazgo? {
        let atributos = try? FileManager.default.attributesOfItem(atPath: video.path)
        let tamaño = (atributos?[.size] as? Int) ?? 0
        let (titulo, temporada, episodio) = tituloLimpio(video)

        var intentos: [(ruta: String, porHash: Bool)] = []
        if tamaño > 0, let h = ((try? hash(de: video)) ?? nil) {
            intentos.append(("/moviebytesize-\(tamaño)/moviehash-\(h)/sublanguageid-spa", true))
        }
        // Un título de una sola palabra corta («mudo», «final») trae cualquier
        // cosa: sin hash que lo respalde no vale la pena arriesgarse.
        if !titulo.isEmpty, titulo.split(separator: " ").count >= 2 || titulo.count >= 6 {
            let q = titulo.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? titulo
            if let temporada, let episodio {
                intentos.append(("/episode-\(episodio)/query-\(q)/season-\(temporada)/sublanguageid-spa", false))
            } else {
                intentos.append(("/query-\(q)/sublanguageid-spa", false))
            }
        }

        let palabrasDelTitulo = Set(titulo.split(separator: " ").filter { $0.count >= 4 }.map(String.init))
        let fichas = Set(video.lastPathComponent.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ". _-")))

        for intento in intentos {
            guard let resultados = try? await pedir(intento.ruta), !resultados.isEmpty else { continue }
            let validos = resultados.filter { ["srt", "ass", "ssa"].contains(($0.SubFormat ?? "srt").lowercased()) }
            guard let mejor = validos.max(by: { puntaje($0, fichas) < puntaje($1, fichas) }) else { continue }

            // Sin hash, exigir que el nombre del subtítulo comparta una palabra
            // larga del título; si no, es otra película.
            if !intento.porHash, !palabrasDelTitulo.isEmpty {
                let nombreSub = (mejor.SubFileName ?? "").lowercased()
                guard palabrasDelTitulo.contains(where: { nombreSub.contains($0) }) else { continue }
            }
            guard let enlace = mejor.SubDownloadLink, let texto = try? await descargar(enlace) else { continue }
            return Hallazgo(texto: texto,
                            nombreDelArchivo: mejor.SubFileName ?? "subtítulo",
                            porHash: intento.porHash)
        }
        return nil
    }

    private static func puntaje(_ r: Resultado, _ fichas: Set<String>) -> Double {
        var n = Double(min(Int(r.SubDownloadsCnt ?? "0") ?? 0, 50_000)) / 5000.0
        if r.MatchedBy == "moviehash" { n += 100 }        // el mismo archivo
        let nombre = (r.SubFileName ?? "").lowercased()
        if nombre.range(of: "latin|americ|mexic", options: .regularExpression) != nil { n += 15 }
        if (r.SubFormat ?? "srt").lowercased() != "srt" { n -= 40 }
        if (Int(r.SubBad ?? "0") ?? 0) > 0 { n -= 30 }
        let coincidencias = fichas.intersection(nombre.components(separatedBy: CharacterSet(charactersIn: ". _-")))
        return n + 3 * Double(coincidencias.count)
    }

    private static func pedir(_ ruta: String) async throws -> [Resultado] {
        var peticion = URLRequest(url: URL(string: base + ruta)!)
        peticion.setValue(agente, forHTTPHeaderField: "User-Agent")
        peticion.timeoutInterval = 25
        let (datos, _) = try await URLSession.shared.data(for: peticion)
        return try JSONDecoder().decode([Resultado].self, from: datos)
    }

    private static func descargar(_ enlace: String) async throws -> String {
        var peticion = URLRequest(url: URL(string: enlace)!)
        peticion.setValue(agente, forHTTPHeaderField: "User-Agent")
        peticion.timeoutInterval = 30
        let (comprimido, _) = try await URLSession.shared.data(for: peticion)
        var datos = descomprimirGzip(comprimido) ?? comprimido
        if datos.starts(with: TextoSRT.bom) { datos = datos.dropFirst(3) }

        if let texto = String(data: datos, encoding: .utf8) { return texto }
        if let texto = String(data: datos, encoding: .windowsCP1252) { return texto }
        return String(decoding: datos, as: UTF8.self)
    }

    // MARK: - gzip

    /// Los subtítulos llegan como .gz. Se salta la cabecera gzip y se infla el
    /// DEFLATE crudo con el framework Compression, sin dependencias externas.
    public static func descomprimirGzip(_ datos: Data) -> Data? {
        guard datos.count > 18, datos[0] == 0x1F, datos[1] == 0x8B, datos[2] == 0x08 else { return nil }
        let banderas = datos[3]
        var i = 10
        if banderas & 0x04 != 0 {                              // campo extra
            guard datos.count > i + 1 else { return nil }
            let largo = Int(datos[i]) | Int(datos[i + 1]) << 8
            i += 2 + largo
        }
        if banderas & 0x08 != 0 { while i < datos.count, datos[i] != 0 { i += 1 }; i += 1 }  // nombre
        if banderas & 0x10 != 0 { while i < datos.count, datos[i] != 0 { i += 1 }; i += 1 }  // comentario
        if banderas & 0x02 != 0 { i += 2 }                     // CRC de la cabecera
        guard i < datos.count - 8 else { return nil }

        let cuerpo = datos.subdata(in: i..<(datos.count - 8))   // sin CRC32 ni tamaño finales
        return inflar(cuerpo)
    }

    private static func inflar(_ cuerpo: Data) -> Data? {
        var flujo = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
                                       src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0,
                                       state: nil)
        guard compression_stream_init(&flujo, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(&flujo) }

        let capacidad = 64 * 1024
        let destino = UnsafeMutablePointer<UInt8>.allocate(capacity: capacidad)
        defer { destino.deallocate() }

        var salida = Data()
        let resultado: Data? = cuerpo.withUnsafeBytes { crudo -> Data? in
            guard let inicio = crudo.bindMemory(to: UInt8.self).baseAddress else { return nil }
            flujo.src_ptr = inicio
            flujo.src_size = cuerpo.count

            while true {
                flujo.dst_ptr = destino
                flujo.dst_size = capacidad
                let estado = compression_stream_process(&flujo, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                salida.append(destino, count: capacidad - flujo.dst_size)
                switch estado {
                case COMPRESSION_STATUS_OK: continue
                case COMPRESSION_STATUS_END: return salida
                default: return nil
                }
            }
        }
        return resultado
    }
}
