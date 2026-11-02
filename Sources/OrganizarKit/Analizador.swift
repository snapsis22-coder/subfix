import Foundation

/// Lo que se entiende del nombre de una descarga.
public enum Lectura: Equatable, Sendable {
    case pelicula(titulo: String, año: Int?)
    /// `episodio` es nil cuando la descarga es una temporada entera.
    case serie(nombre: String, temporada: Int, episodio: Int?)

    /// La carpeta con la que Jellyfin y Plex la reconocen: `Verity (2026)` o `Tulsa King`.
    public var carpeta: String {
        switch self {
        case .pelicula(let titulo, let año):
            return año.map { "\(titulo) (\($0))" } ?? titulo
        case .serie(let nombre, _, _):
            return nombre
        }
    }

    /// `Season 04`, con dos cifras: así se ordenan bien en el Finder.
    public var carpetaDeTemporada: String? {
        guard case .serie(_, let temporada, _) = self else { return nil }
        return String(format: "Season %02d", temporada)
    }

    public var esSerie: Bool {
        if case .serie = self { return true } else { return false }
    }
}

/// Entiende nombres como `Verity.2026.REPACK.2160p.AMZN.WEB-DL.mkv` o
/// `Tulsa King S04E02 Blind Rooster 2160p ATV WEB-DL`.
///
/// La regla es la misma que usa Plex: lo que va antes del `S04E02` es la serie, y en
/// las películas lo que va antes del año es el título. Todo lo de después (calidad,
/// grupo, códec) sobra.
public enum Analizador {

    public static let extensionesDeVideo: Set<String> = [
        "mkv", "mp4", "m4v", "avi", "mov", "ts", "m2ts", "wmv", "webm", "mpg", "mpeg",
    ]

    public static func esVideo(_ url: URL) -> Bool {
        extensionesDeVideo.contains(url.pathExtension.lowercased())
    }

    public static func leer(_ nombre: String) -> Lectura? {
        var texto = nombre
        if extensionesDeVideo.contains((nombre as NSString).pathExtension.lowercased()) {
            texto = (nombre as NSString).deletingPathExtension
        }
        texto = separar(texto)

        // Episodio: S04E02, s4e2, 4x02.
        if let m = buscar(#"(?i)\bS(\d{1,2}) ?E(\d{1,3})\b"#, en: texto)
            ?? buscar(#"(?i)\b(\d{1,2})x(\d{2,3})\b"#, en: texto) {
            let serie = limpiarSerie(String(texto[..<m.rango.lowerBound]))
            guard !serie.isEmpty, let temporada = Int(m.grupos[0]) else { return nil }
            return .serie(nombre: serie, temporada: temporada, episodio: Int(m.grupos[1]))
        }

        // Temporada entera: «Season 4», «Temporada 2», «S03» suelto.
        if let m = buscar(#"(?i)\b(?:season|temporada) ?(\d{1,2})\b"#, en: texto)
            ?? buscar(#"(?i)\bS(\d{1,2})\b"#, en: texto) {
            let serie = limpiarSerie(String(texto[..<m.rango.lowerBound]))
            guard !serie.isEmpty, let temporada = Int(m.grupos[0]) else { return nil }
            return .serie(nombre: serie, temporada: temporada, episodio: nil)
        }

        // Película: el título es lo que va antes del ÚLTIMO año creíble, para que
        // «Blade Runner 2049 (2017)» no se corte en el 2049.
        let tope = Calendar.current.component(.year, from: Date()) + 1
        let años = todas(#"(?<!\d)(19\d{2}|20\d{2})(?!\d)"#, en: texto).filter {
            $0.rango.lowerBound > texto.startIndex && (Int($0.grupos[0]) ?? 0) <= tope
        }
        if let año = años.last {
            let titulo = limpiarTitulo(String(texto[..<año.rango.lowerBound]))
            if !titulo.isEmpty { return .pelicula(titulo: titulo, año: Int(año.grupos[0])) }
        }

        // Sin año: se corta en la primera palabra de calidad y se pide revisar.
        var titulo = texto
        if let basura = buscar(#"(?i)\b(2160p|1080p|720p|480p|4k|uhd|web[ -]?dl|webrip|web|bluray|brrip|bdrip|hdrip|dvdrip|x26[45]|h ?26[45]|hevc|remux|repack|proper|remastered|ddp?5|aac|atmos|hdr|dv)\b"#, en: texto) {
            titulo = String(texto[..<basura.rango.lowerBound])
        }
        titulo = limpiarTitulo(titulo)
        return titulo.isEmpty ? nil : .pelicula(titulo: titulo, año: nil)
    }

    // MARK: - Limpieza

    /// Puntos y guiones bajos a espacios, y fuera lo que vaya entre corchetes:
    /// `[YTS.BZ]`, `[Ben The Men]`, `{tag}`.
    static func separar(_ texto: String) -> String {
        var t = texto
        t = t.replacingOccurrences(of: #"\[[^\]]*\]|\{[^}]*\}"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
        return colapsar(t)
    }

    static func limpiarTitulo(_ texto: String) -> String {
        var t = texto.replacingOccurrences(of: #"\([^)]*$"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "()", with: "")
        t = colapsar(t).trimmingCharacters(in: CharacterSet(charactersIn: " -–(,"))
        return paraCarpeta(capitalizarSiHaceFalta(t))
    }

    /// El año no va en la carpeta de la serie: «Ted Lasso (2022)» confunde la búsqueda
    /// cuando el año es el de la temporada y no el del estreno.
    static func limpiarSerie(_ texto: String) -> String {
        var t = texto.replacingOccurrences(of: #"\(\s*(19|20)\d{2}\s*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s(19|20)\d{2}\s*$"#, with: "", options: .regularExpression)
        return limpiarTitulo(t)
    }

    /// `THE INVITE` → `The Invite`. Si ya viene con mayúsculas y minúsculas, se respeta.
    static func capitalizarSiHaceFalta(_ texto: String) -> String {
        let letras = texto.filter(\.isLetter)
        guard !letras.isEmpty else { return texto }
        if letras == letras.uppercased() || letras == letras.lowercased() {
            return texto.lowercased().capitalized
        }
        return texto
    }

    /// Los dos puntos y la barra no pueden ir en un nombre de carpeta.
    static func paraCarpeta(_ texto: String) -> String {
        texto.replacingOccurrences(of: ":", with: " -").replacingOccurrences(of: "/", with: "-")
    }

    static func colapsar(_ texto: String) -> String {
        texto.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Expresiones regulares

    struct Coincidencia {
        let rango: Range<String.Index>
        let grupos: [String]
    }

    static func buscar(_ patron: String, en texto: String) -> Coincidencia? {
        todas(patron, en: texto).first
    }

    static func todas(_ patron: String, en texto: String) -> [Coincidencia] {
        guard let regex = try? NSRegularExpression(pattern: patron) else { return [] }
        let completo = NSRange(texto.startIndex..., in: texto)
        return regex.matches(in: texto, range: completo).compactMap { m in
            guard let rango = Range(m.range, in: texto) else { return nil }
            let grupos = (1..<max(m.numberOfRanges, 1)).map { i -> String in
                guard let r = Range(m.range(at: i), in: texto) else { return "" }
                return String(texto[r])
            }
            return Coincidencia(rango: rango, grupos: grupos)
        }
    }
}
