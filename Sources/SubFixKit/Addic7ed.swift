import Foundation

/// Subtítulos en español latino para series, desde Addic7ed.
///
/// Los WEB-DL de series suelen traer embebido sólo el español de España
/// («¿Quiénes sois?», «tío», «vale»). Addic7ed separa el latino (idioma 6) del
/// castellano (5) y sus versiones WEB van sincronizadas con los WEB-DL.
/// Subdivx no sirve desde una app: responde con un desafío de Cloudflare.
public enum Addic7ed {

    static let base = "https://www.addic7ed.com"
    static let idiomaLatino = 6
    static let agente = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                      + "(KHTML, like Gecko) Chrome/140.0 Safari/537.36"

    public struct Version: Equatable {
        public let nombre: String          // «ION10+OATH+SKEDADDLE+TRUMP»
        public let enlace: String          // «/original/159773/31»
        public let completa: Bool
        public let paraSordos: Bool
        public let descargas: Int
    }

    public struct Hallazgo {
        public let texto: String
        public let version: String

        public var explicacion: String { "Addic7ed, latino (versión \(version))" }
    }

    // MARK: - Página del episodio

    /// «ted lasso» → «Ted_Lasso». En minúsculas Addic7ed devuelve una página vacía.
    public static func nombreEnURL(_ titulo: String) -> String {
        titulo.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "_")
    }

    /// Cada versión es una tabla que abre con `class="NewsTitle"`; dentro, una
    /// fila por idioma con su estado y su botón de descarga.
    public static func versiones(en html: String) -> [Version] {
        var resultado: [Version] = []
        for bloque in html.components(separatedBy: "class=\"NewsTitle\"").dropFirst() {
            guard let nombre = primera("Version (.*?),", en: bloque),
                  let enlace = primera("href=\"(/(?:original|updated)/[^\"]+)\"", en: bloque)
            else { continue }
            let estado = primera("<b>\\s*(.*?)\\s*</b>", en: bloque) ?? ""
            resultado.append(Version(
                nombre: nombre,
                enlace: enlace,
                completa: estado.hasPrefix("Completed"),
                paraSordos: bloque.contains("title=\"Hearing Impaired\""),
                descargas: Int(primera("(\\d+) Downloads", en: bloque) ?? "") ?? 0))
        }
        return resultado
    }

    /// Mayor es mejor: la versión que comparta más fichas con el nombre del
    /// archivo (WEB-DL, ATVP, NTb…) es la que va sincronizada con él.
    static func puntaje(_ version: Version, fichas: Set<String>) -> Double {
        let suyas = Set(version.nombre.lowercased().components(separatedBy: CharacterSet(charactersIn: "+.-_ ")))
        var n = 5 * Double(suyas.intersection(fichas).count)
        if version.paraSordos { n -= 2 }
        return n + Double(min(version.descargas, 5000)) / 1000
    }

    // MARK: - Búsqueda

    public static func buscarLatino(para video: URL) async -> Hallazgo? {
        let (titulo, temporada, episodio) = OpenSubtitles.tituloLimpio(video)
        guard !titulo.isEmpty, let temporada, let episodio else { return nil }

        let pagina = "\(base)/serie/\(nombreEnURL(titulo))/\(temporada)/\(episodio)/\(idiomaLatino)"
        guard let html = try? await pedir(pagina, referer: base) else { return nil }

        let fichas = Set(video.lastPathComponent.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ". _-[]")))
        let candidatas = versiones(en: html).filter(\.completa)
            .sorted { puntaje($0, fichas: fichas) > puntaje($1, fichas: fichas) }

        for version in candidatas {
            guard let texto = try? await pedir(base + version.enlace, referer: pagina),
                  texto.contains("-->")       // al pasar el cupo diario llega una página HTML
            else { continue }
            return Hallazgo(texto: texto, version: version.nombre)
        }
        return nil
    }

    /// Sin el Referer de la página del episodio, la descarga redirige a la portada.
    private static func pedir(_ direccion: String, referer: String) async throws -> String {
        guard let url = URL(string: direccion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                            ?? direccion) else { throw URLError(.badURL) }
        var peticion = URLRequest(url: url)
        peticion.setValue(agente, forHTTPHeaderField: "User-Agent")
        peticion.setValue(referer, forHTTPHeaderField: "Referer")
        peticion.timeoutInterval = 25
        let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
        guard (respuesta as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        var cuerpo = datos
        if cuerpo.starts(with: TextoSRT.bom) { cuerpo = cuerpo.dropFirst(3) }
        if let texto = String(data: cuerpo, encoding: .utf8) { return texto }
        return String(data: cuerpo, encoding: .windowsCP1252) ?? String(decoding: cuerpo, as: UTF8.self)
    }

    private static func primera(_ patron: String, en texto: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: patron, options: .dotMatchesLineSeparators),
              let m = regex.firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: texto)
        else { return nil }
        return String(texto[r])
    }
}
