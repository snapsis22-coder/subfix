import Foundation

/// Una pista de subtítulo dentro del contenedor, tal como la ve ffprobe.
public struct Pista: Identifiable, Hashable, Sendable {
    public let indice: Int
    public let codec: String
    public let idioma: String?
    public let titulo: String?
    public let forzada: Bool
    public let paraSordos: Bool

    public var id: Int { indice }

    public init(indice: Int, codec: String, idioma: String?, titulo: String?,
                forzada: Bool, paraSordos: Bool) {
        self.indice = indice
        self.codec = codec
        self.idioma = idioma
        self.titulo = titulo
        self.forzada = forzada
        self.paraSordos = paraSordos
    }

    /// Códecs que son texto: se pueden convertir a SRT.
    public static let deTexto: Set<String> = ["subrip", "ass", "ssa", "mov_text", "webvtt", "text", "srt"]
    /// Códecs que son mapas de bits: harían falta OCR.
    public static let deImagen: Set<String> = ["hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle", "xsub"]

    public var esTexto: Bool { Self.deTexto.contains(codec) }
    public var esImagen: Bool { Self.deImagen.contains(codec) }

    public var esEspañol: Bool {
        let campos = "\(idioma ?? "") \(titulo ?? "")".lowercased()
        return ["spa", "es", "esp", "spanish", "castellano", "lat"].contains { termino in
            campos.range(of: "\\b\(termino)\\b", options: .regularExpression) != nil
        }
    }

    var esLatino: Bool {
        guard let titulo else { return false }
        return titulo.range(of: "latin|americ|mexic", options: [.regularExpression, .caseInsensitive]) != nil
    }

    var descartable: Bool {
        guard let titulo else { return false }
        return titulo.range(of: "forced|forzad|sdh|hearing|comentario|commentary",
                            options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Mayor es mejor: el latino primero, las forzadas y para sordos al final.
    var puntaje: Int {
        var n = 0
        if esLatino { n += 10 }
        if codec == "subrip" { n += 2 }     // ya es SRT: se copia sin reconvertir
        if forzada || descartable { n -= 20 }
        if paraSordos { n -= 5 }
        return n
    }

    public var resumen: String {
        var partes = ["#\(indice)", codec, idioma ?? "sin idioma"]
        if let titulo, !titulo.isEmpty { partes.append(titulo) }
        if forzada { partes.append("[forced]") }
        return partes.joined(separator: " · ")
    }
}

// MARK: - Sondeo con ffprobe

public enum Sondeo {

    private struct RespuestaFFProbe: Decodable {
        struct Flujo: Decodable {
            let index: Int
            let codec_name: String?
            let tags: [String: String]?
            let disposition: [String: Int]?
        }
        let streams: [Flujo]?
    }

    /// Devuelve las pistas de subtítulo con su índice real dentro del archivo.
    /// Contar a mano desde un listado de tracker no sirve: omite video y audio.
    public static func pistas(de url: URL) throws -> [Pista] {
        let salida = try Herramientas.correr("ffprobe", [
            "-v", "error", "-select_streams", "s",
            "-show_entries",
            "stream=index,codec_name:stream_tags=language,title:stream_disposition=forced,hearing_impaired",
            "-print_format", "json", url.path,
        ])
        guard salida.codigo == 0 else {
            throw ErrorDeSubFix.noSePudoSondear(salida.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let datos = Data(salida.texto.utf8)
        let respuesta = try JSONDecoder().decode(RespuestaFFProbe.self, from: datos)
        return (respuesta.streams ?? []).map { flujo in
            Pista(indice: flujo.index,
                  codec: flujo.codec_name ?? "desconocido",
                  idioma: flujo.tags?["language"],
                  titulo: flujo.tags?["title"],
                  forzada: (flujo.disposition?["forced"] ?? 0) == 1,
                  paraSordos: (flujo.disposition?["hearing_impaired"] ?? 0) == 1)
        }
    }

    /// De las candidatas, la mejor. Devuelve también si hubo empate real, para
    /// que la interfaz pueda ofrecer el cambio en vez de decidir a ciegas.
    public static func mejor(entre candidatas: [Pista]) -> (elegida: Pista, huboEmpate: Bool)? {
        let ordenadas = candidatas.sorted { $0.puntaje > $1.puntaje }
        guard let primera = ordenadas.first else { return nil }
        let empatadas = ordenadas.filter { $0.puntaje == primera.puntaje }
        return (primera, empatadas.count > 1)
    }

    /// Extrae la pista a un .srt temporal.
    public static func extraer(pista: Pista, de video: URL, a destino: URL) throws {
        // subrip ya es SRT: copiar es instantáneo y no reformatea los tiempos.
        let modo = pista.codec == "subrip" ? ["-c:s", "copy"] : ["-c:s", "srt"]
        let salida = try Herramientas.correr("ffmpeg", [
            "-nostdin", "-v", "error", "-y", "-i", video.path,
            "-map", "0:\(pista.indice)",
        ] + modo + [destino.path])

        let atributos = try? FileManager.default.attributesOfItem(atPath: destino.path)
        let tamaño = (atributos?[.size] as? Int) ?? 0
        guard salida.codigo == 0, tamaño > 0 else {
            throw ErrorDeSubFix.fallóLaExtracción(salida.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
