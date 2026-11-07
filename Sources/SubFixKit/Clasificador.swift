import Foundation

/// Lo que una pista de subtítulo es de verdad, leyendo su texto: muchas descargas traen
/// tres «spa» sin título ni marcas (Heart of the Beast, 7-nov) y solo el contenido dice
/// cuál es el latino completo, cuál el de España y cuál el forzado.
public struct Variante: Hashable, Sendable {
    public enum Region: String, Sendable { case latino, españa }

    public var region: Region?
    /// Sólo carteles y diálogos en otro idioma: pocas líneas.
    public var forzado: Bool
    /// Con descripciones de sonido: «[MOTOR SE APAGA]».
    public var paraSordos: Bool
    public var lineas: Int

    public init(region: Region? = nil, forzado: Bool = false, paraSordos: Bool = false, lineas: Int = 0) {
        self.region = region
        self.forzado = forzado
        self.paraSordos = paraSordos
        self.lineas = lineas
    }

    /// «Latino», «España», «Forzado», «Para sordos»: lo que se muestra junto a la pista.
    public var etiquetas: [String] {
        var t: [String] = []
        switch region {
        case .latino: t.append("Latino")
        case .españa: t.append("España")
        case nil: break
        }
        if forzado { t.append("Forzado") }
        if paraSordos { t.append("Para sordos") }
        return t
    }
}

public enum Clasificador {

    /// Sólo se leen las pistas de texto en español, inglés o sin idioma: extraer cuesta leer
    /// el archivo entero, y es donde están las dudas (latino/España, forzado, para sordos).
    public static func seLee(_ pista: Pista) -> Bool {
        pista.esTexto && (pista.esEspañol || pista.esLatino || esIngles(pista) || pista.sinIdioma)
    }

    public static func esIngles(_ pista: Pista) -> Bool {
        let campos = "\(pista.idioma ?? "") \(pista.titulo ?? "")".lowercased()
        return campos.range(of: #"\b(eng|en|english)\b"#, options: .regularExpression) != nil
    }

    /// Extrae las pistas que valen la pena (de una sola pasada por el archivo) y las clasifica.
    /// Lo que no se pudo leer simplemente no aparece en el resultado.
    public static func clasificar(_ pistas: [Pista], de video: URL) -> [Int: Variante] {
        let elegidas = pistas.filter(seLee)
        guard !elegidas.isEmpty else { return [:] }
        let carpeta = FileManager.default.temporaryDirectory
            .appendingPathComponent("subfix-clasificar-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: carpeta) }

        var args = ["-nostdin", "-v", "error", "-y", "-i", video.path]
        for pista in elegidas {
            args += ["-map", "0:\(pista.indice)", "-c:s", pista.codec == "subrip" ? "copy" : "srt",
                     carpeta.appendingPathComponent("\(pista.indice).srt").path]
        }
        _ = try? Herramientas.correr("ffmpeg", args)

        var textos: [Int: String] = [:]
        for pista in elegidas {
            let url = carpeta.appendingPathComponent("\(pista.indice).srt")
            if let texto = try? TextoSRT.leer(url).texto, TextoSRT.esSRT(texto) { textos[pista.indice] = texto }
        }
        return clasificar(pistas: elegidas, textos: textos)
    }

    /// La parte que decide, sin tocar archivos (para las pruebas).
    public static func clasificar(pistas: [Pista], textos: [Int: String]) -> [Int: Variante] {
        enum Grupo { case español, ingles, otro }
        var lineas: [Int: Int] = [:]
        var grupos: [Int: Grupo] = [:]
        for pista in pistas {
            guard let texto = textos[pista.indice] else { continue }
            lineas[pista.indice] = texto.components(separatedBy: "-->").count - 1
            if pista.esEspañol || pista.esLatino { grupos[pista.indice] = .español }
            else if esIngles(pista) { grupos[pista.indice] = .ingles }
            else { grupos[pista.indice] = TextoSRT.pareceEspañol(cuerpo(texto)) ? .español : .otro }
        }

        var resultado: [Int: Variante] = [:]
        for pista in pistas {
            guard let texto = textos[pista.indice], let n = lineas[pista.indice], let grupo = grupos[pista.indice] else { continue }
            let hermanas = pistas.filter { grupos[$0.indice] == grupo }.compactMap { lineas[$0.indice] }
            let mayor = hermanas.max() ?? n
            let titulo = pista.titulo ?? ""

            var v = Variante(lineas: n)
            v.forzado = pista.forzada || dice(titulo, #"forced|forzad"#)
                || (mayor >= 100 && Double(n) < Double(mayor) * 0.3)
            v.paraSordos = pista.paraSordos || dice(titulo, #"\bsdh\b|sordos|hearing|\bcc\b"#)
                || descripcionesDeSonido(texto) >= max(10, n / 10)

            if grupo == .español {
                if pista.esLatino { v.region = .latino }
                else if dice(titulo, #"castil|castellano|espa[ñn]a|spain|\bes-es\b|europe"#) { v.region = .españa }
                else if !v.forzado {
                    if TextoSRT.pareceDeEspaña(texto) || puntajeDeEspaña(texto) >= 10 { v.region = .españa }
                    else if n >= 50 { v.region = .latino }   // completo y sin rasgos de España
                }
            }
            resultado[pista.indice] = v
        }

        // Dos completos en español sin rótulo: el que tiene claramente más rasgos de España lo es,
        // aunque tenga pocos (Heart of the Beast: 1 «vosotros» pero 14 «vale» y 4 «joder»; el otro, cero).
        let completos = pistas.filter { grupos[$0.indice] == .español && resultado[$0.indice]?.forzado == false
            && !$0.esLatino && !dice($0.titulo ?? "", #"castil|castellano|espa[ñn]a|spain|\bes-es\b|europe"#) }
        if completos.count >= 2 {
            let puntajes = completos.map { ($0.indice, textos[$0.indice].map(puntajeDeEspaña) ?? 0) }
                .sorted { $0.1 > $1.1 }
            let (indice, mayor) = puntajes[0], segundo = puntajes[1].1
            if mayor >= 4, mayor >= 4 * (segundo + 1) { resultado[indice]?.region = .españa }
        }

        // Un forzado casi no tiene diálogo para delatar su región: se parece al completo de
        // su misma traducción («EN ALGÚN LUGAR DE ALASKA» contra «EN ALGUNA PARTE…»).
        for pista in pistas where resultado[pista.indice]?.forzado == true && resultado[pista.indice]?.region == nil
            && grupos[pista.indice] == .español {
            guard let propias = textos[pista.indice].map(frases) else { continue }
            var mejor: (Variante.Region, Int)?
            for otra in pistas where otra.indice != pista.indice && grupos[otra.indice] == .español {
                guard let region = resultado[otra.indice]?.region, resultado[otra.indice]?.forzado == false,
                      let suyas = textos[otra.indice].map(frases) else { continue }
                let comunes = propias.intersection(suyas).count
                if comunes > (mejor?.1 ?? 0) { mejor = (region, comunes) }
            }
            if let mejor { resultado[pista.indice]?.region = mejor.0 }
        }
        return resultado
    }

    /// Vocabulario de España que el doblaje latino no usa: «vale» como muletilla (no «vale la
    /// pena»), «tío/tía» (no «tío Roy»: parentesco seguido de nombre), «joder», «gilipollas»…
    static let lexicoDeEspaña = try! NSRegularExpression(
        pattern: #"\b(joder|gilipollas|coño|hostias?|cabr[oó]n(?:es)?|chaval(?:a|es)?|mola|guay|ordenador|m[oó]vil|flipa\p{L}*|t[ií][oa]s?(?![ \t]+\p{Lu}))\b|(?:^|[¿¡,.\-][ \t]*)vale(?=[ \t]*[.,!?…]|[ \t]*$)"#,
        options: [.caseInsensitive, .anchorsMatchLines])

    /// Cuánto huele a España: cada forma de «vosotros» vale 3; cada palabra del léxico, 1.
    public static func puntajeDeEspaña(_ texto: String) -> Int {
        let rango = NSRange(texto.startIndex..., in: texto)
        return 3 * TextoSRT.rasgosDeEspaña.numberOfMatches(in: texto, range: rango)
            + lexicoDeEspaña.numberOfMatches(in: texto, range: rango)
    }

    private static func dice(_ texto: String, _ patron: String) -> Bool {
        texto.range(of: patron, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// «[MOTOR SE APAGA]», «(SUSPIRA)»: cuántas hay.
    static func descripcionesDeSonido(_ texto: String) -> Int {
        let regex = try! NSRegularExpression(pattern: #"[\[(][^\])\n]{2,60}[\])]"#)
        return regex.numberOfMatches(in: texto, range: NSRange(texto.startIndex..., in: texto))
    }

    /// Sólo el diálogo: sin números de bloque ni tiempos.
    static func cuerpo(_ texto: String) -> String {
        texto.components(separatedBy: .newlines)
            .filter { linea in
                let l = linea.trimmingCharacters(in: .whitespaces)
                return !l.isEmpty && !l.contains("-->") && Int(l) == nil
            }
            .joined(separator: "\n")
    }

    /// Cada línea de diálogo normalizada (sin tildes, mayúsculas ni puntuación) para comparar traducciones.
    static func frases(_ texto: String) -> Set<String> {
        Set(cuerpo(texto).components(separatedBy: .newlines).map { linea in
            linea.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }.filter { $0.count >= 4 })
    }
}
