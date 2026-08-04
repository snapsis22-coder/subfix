import Foundation

/// Lectura, saneado y escritura de archivos .srt.
///
/// Los tres requisitos del reproductor Tizen del RU7400 son: nombre base
/// idéntico al video (lo pone quien llama), BOM UTF-8 y saltos CRLF. Sin el BOM
/// el firmware adivina la codificación, cae en Latin-1 y las tildes salen como
/// basura — que es el síntoma que se venía arrastrando.
public enum TextoSRT {

    public static let bom = Data([0xEF, 0xBB, 0xBF])

    /// Lee un .srt de origen desconocido sin romper las tildes. Devuelve también
    /// qué codificación resultó, que es información útil para el usuario.
    public static func leer(_ url: URL) throws -> (texto: String, codificacion: String) {
        var datos = try Data(contentsOf: url)
        if datos.starts(with: bom) { datos = datos.dropFirst(3) }

        if let texto = String(data: datos, encoding: .utf8) {
            return (texto, "UTF-8")
        }
        if let texto = String(data: datos, encoding: .windowsCP1252) {
            return (texto, "Windows-1252")
        }
        return (String(decoding: datos, as: UTF8.self), "Latin-1 (con reemplazos)")
    }

    /// Escribe con BOM UTF-8 y CRLF. Toda salida de la app pasa por aquí.
    public static func escribirParaElTV(_ texto: String, en url: URL) throws {
        let normalizado = texto
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        var datos = bom
        datos.append(Data(normalizado.utf8))
        try datos.write(to: url, options: .atomic)
    }

    /// ¿Un .srt que ya existe cumple lo que el TV necesita?
    public static func estaBienFormado(_ url: URL) -> Bool {
        guard let datos = try? Data(contentsOf: url), datos.starts(with: bom) else { return false }
        return datos.range(of: Data([0x0D, 0x0A])) != nil
    }

    /// Nunca se pisa un archivo del usuario: el anterior se corre a «.anterior».
    @discardableResult
    public static func apartar(_ url: URL) throws -> URL {
        var destino = url.appendingPathExtension("anterior")
        var n = 2
        while FileManager.default.fileExists(atPath: destino.path) {
            destino = url.appendingPathExtension("anterior\(n)")
            n += 1
        }
        try FileManager.default.moveItem(at: url, to: destino)
        return destino
    }

    // MARK: - Etiquetas de formato ASS

    /// Las pistas ASS traen etiquetas entre llaves: `{\an8}` sube la línea para que no
    /// tape algo que ya está en pantalla, `{\i1}` la pone en cursiva, `{\pos(x,y)}` la
    /// coloca en un punto exacto. VLC o Infuse las interpretan; el Tizen del televisor
    /// no las conoce y las imprime tal cual, así que se lee "{\an8}Calma, Caraxes.".
    ///
    /// Sólo se borra la llave cuyo contenido empieza por barra invertida: un diálogo que
    /// legítimamente diga {algo} se queda intacto.
    static let etiquetaASS = try! NSRegularExpression(pattern: "\\{\\s*\\\\[^{}]*\\}")
    /// Un dibujo vectorial, al quitarle las llaves, deja una ristra de comandos y
    /// coordenadas ("m 0 0 l 100 0 b 5 5 …") que no es diálogo y no debe mostrarse.
    static let dibujoASS = try! NSRegularExpression(pattern: "^[mnlbspc\\s\\d.,+-]+$",
                                                    options: [.caseInsensitive])
    static let marcaDibujo = try! NSRegularExpression(pattern: "\\\\p\\s*[1-9]")

    public static func quitarEtiquetasASS(_ texto: String) -> (texto: String, tocadas: Int) {
        let bloques = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: try! NSRegularExpression(pattern: "\r?\n\\s*\r?\n"))
        var salida: [String] = []
        var tocadas = 0

        for bloque in bloques {
            let lineas = bloque.components(separatedBy: "\n")
            guard let corte = lineas.firstIndex(where: { $0.contains("-->") }) else {
                salida.append(bloque)          // bloque raro: no se toca
                continue
            }
            let cabecera = Array(lineas[...corte])
            var cuerpo: [String] = []
            for linea in lineas[(corte + 1)...] {
                let eraDibujo = coincide(marcaDibujo, linea)
                var limpia = etiquetaASS.stringByReplacingMatches(
                    in: linea, range: NSRange(linea.startIndex..., in: linea), withTemplate: "")
                // \N salto duro, \h espacio irrompible, \n salto blando (= espacio).
                limpia = limpia.replacingOccurrences(of: "\\N", with: "\n")
                limpia = limpia.replacingOccurrences(of: "\\h", with: " ")
                limpia = limpia.replacingOccurrences(of: "\\n", with: " ")
                if limpia != linea { tocadas += 1 }
                for trozo in limpia.components(separatedBy: "\n") {
                    let t = trozo.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { continue }
                    if eraDibujo, coincide(dibujoASS, t) { continue }
                    cuerpo.append(t)
                }
            }
            if !cuerpo.isEmpty {               // si queda vacío, el bloque sobra
                salida.append((cabecera + cuerpo).joined(separator: "\n"))
            }
        }
        guard tocadas > 0 else { return (texto, 0) }
        return (renumerar(salida), tocadas)
    }

    private static func coincide(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Tras quitar bloques hay que renumerar, o el reproductor ve saltos en la cuenta.
    private static func renumerar(_ bloques: [String]) -> String {
        let renumerados = bloques.enumerated().map { indice, bloque -> String in
            var lineas = bloque.components(separatedBy: "\n")
            if let primera = lineas.first, Int(primera.trimmingCharacters(in: .whitespaces)) != nil {
                lineas[0] = String(indice + 1)
            }
            return lineas.joined(separator: "\n")
        }
        return renumerados.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Publicidad

    /// Los subtituladores meten propaganda en el primer y último bloque. Sólo se
    /// miran esos dos extremos, para no borrar diálogo por un falso positivo.
    static let spam = try! NSRegularExpression(
        pattern: "opensubtitles|subdivx|addic7ed|www\\.|http|"
               + "\\b[\\w-]{3,}\\.(?:com|net|org|io|app|tv|link|info|co|me)\\b|"
               + "-=\\[|watch online|free download|traducido por|subtitulado por|"
               + "resync|corregido por|@\\w+",
        options: [.caseInsensitive])

    public static func quitarPublicidad(_ texto: String) -> (texto: String, quitados: Int) {
        var bloques = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: try! NSRegularExpression(pattern: "\r?\n\\s*\r?\n"))
        var quitados = 0

        while bloques.count > 2, esPublicidad(bloques[0]) {
            bloques.removeFirst(); quitados += 1
        }
        while bloques.count > 2, esPublicidad(bloques[bloques.count - 1]) {
            bloques.removeLast(); quitados += 1
        }
        guard quitados > 0 else { return (texto, 0) }
        return (renumerar(bloques), quitados)
    }

    private static func esPublicidad(_ bloque: String) -> Bool {
        // Sin el número ni la línea de tiempos: sólo el diálogo.
        let cuerpo = bloque.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n")
        guard !cuerpo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let rango = NSRange(cuerpo.startIndex..., in: cuerpo)
        return spam.firstMatch(in: cuerpo, range: rango) != nil
    }
}

extension String {
    /// Partir por expresión regular, que Foundation no trae de serie.
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let texto = self
        let rango = NSRange(texto.startIndex..., in: texto)
        var partes: [String] = []
        var inicio = texto.startIndex
        regex.enumerateMatches(in: texto, range: rango) { coincidencia, _, _ in
            guard let coincidencia, let r = Range(coincidencia.range, in: texto) else { return }
            partes.append(String(texto[inicio..<r.lowerBound]))
            inicio = r.upperBound
        }
        partes.append(String(texto[inicio...]))
        return partes
    }
}
