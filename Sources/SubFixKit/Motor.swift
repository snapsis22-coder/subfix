import Foundation

public enum Motor {

    public static let extensionesDeVideo: Set<String> = ["mkv", "mp4", "m4v", "avi", "mov", "ts", "webm"]
    public static let extensionesDeSubtitulo: Set<String> = ["srt", "ass", "ssa", "vtt"]

    // MARK: - Diagnóstico (rápido, sin tocar la red ni escribir nada)

    public struct Diagnostico: Sendable {
        public let pistas: [Pista]
        public let elegida: Pista?
        public let hayEmpate: Bool
        public let suelto: URL?
        public let srtExistente: URL?
        public let srtBienFormado: Bool
        public let error: String?

        public var pistasDeImagen: [Pista] { pistas.filter(\.esImagen) }

        /// Lo que se hará al procesar, en una línea para la lista.
        public var plan: String {
            if let error { return error }
            if srtExistente != nil { return srtBienFormado ? "Ya tiene subtítulo correcto" : "Reparar el .srt existente" }
            if let elegida { return "Extraer \(elegida.codec) · \(elegida.idioma ?? "?")" }
            if let suelto { return "Usar \(suelto.lastPathComponent)" }
            if !pistasDeImagen.isEmpty { return "Sólo imagen — buscar en OpenSubtitles" }
            return "Sin subtítulos — buscar en OpenSubtitles"
        }

        /// Lo mismo que `plan`, contando con que se busque latino para las series.
        public func plan(preferirLatino: Bool) -> String {
            guard preferirLatino, esEpisodio, error == nil, srtExistente == nil,
                  elegida?.esLatino != true else { return plan }
            if let elegida { return "Buscar latino en Addic7ed · si no hay, \(elegida.codec) · \(elegida.idioma ?? "?")" }
            return "Buscar latino en Addic7ed"
        }

        public var esEpisodio: Bool { carpeta != nil }
        /// «Ted Lasso S01E01» si el archivo es un capítulo de serie.
        public let carpeta: String?

        public var necesitaRed: Bool {
            srtExistente == nil && elegida == nil && suelto == nil
        }
    }

    public static func diagnosticar(_ video: URL) -> Diagnostico {
        let destino = destinoSRT(de: video)
        let existente = FileManager.default.fileExists(atPath: destino.path) ? destino : nil
        let carpeta = carpetaDeCapitulo(para: video)

        do {
            let pistas = try Sondeo.pistas(de: video)
            let deTexto = pistas.filter(\.esTexto)
            let candidatas = deTexto.filter(\.esEspañol).isEmpty ? deTexto : deTexto.filter(\.esEspañol)
            let mejor = Sondeo.mejor(entre: candidatas)
            return Diagnostico(pistas: pistas,
                               elegida: mejor?.elegida,
                               hayEmpate: mejor?.huboEmpate ?? false,
                               suelto: mejor == nil ? sueltoPara(video) : nil,
                               srtExistente: existente,
                               srtBienFormado: existente.map(TextoSRT.estaBienFormado) ?? false,
                               error: nil, carpeta: carpeta)
        } catch {
            return Diagnostico(pistas: [], elegida: nil, hayEmpate: false, suelto: nil,
                               srtExistente: existente,
                               srtBienFormado: existente.map(TextoSRT.estaBienFormado) ?? false,
                               error: error.localizedDescription, carpeta: carpeta)
        }
    }

    // MARK: - Proceso

    public enum Resultado: Sendable {
        case listo(origen: String, lineas: Int, publicidadQuitada: Int, etiquetasLimpiadas: Int,
                   caracteresDepurados: Int)
        case reparado(codificacionAnterior: String)
        case yaEstaba
        case sinSubtitulos(soloImagen: Bool)
        case falló(String)

        public var fueBien: Bool {
            switch self {
            case .listo, .reparado, .yaEstaba: return true
            default: return false
            }
        }
    }

    public struct Opciones: Sendable {
        public var usarRed: Bool
        public var forzar: Bool
        public var pistaPreferida: Int?
        /// En series, buscar primero el latino en Addic7ed aunque el archivo
        /// traiga una pista en español (casi siempre es la de España).
        public var preferirLatino: Bool

        public init(usarRed: Bool = true, forzar: Bool = false, pistaPreferida: Int? = nil,
                    preferirLatino: Bool = false) {
            self.usarRed = usarRed
            self.forzar = forzar
            self.pistaPreferida = pistaPreferida
            self.preferirLatino = preferirLatino
        }
    }

    public static func procesar(_ video: URL, opciones: Opciones = Opciones()) async -> Resultado {
        let destino = destinoSRT(de: video)

        // Existir no basta: los .srt que vienen con el torrent suelen estar en
        // Latin-1 y sin CRLF, que es justo lo que el TV pinta como basura.
        if FileManager.default.fileExists(atPath: destino.path), !opciones.forzar {
            if TextoSRT.estaBienFormado(destino) { return .yaEstaba }
            do {
                let (texto, codificacion) = try TextoSRT.leer(destino)
                try TextoSRT.apartar(destino)
                try TextoSRT.escribirParaElTV(TextoSRT.depurarCaracteres(texto).texto, en: destino)
                return .reparado(codificacionAnterior: codificacion)
            } catch {
                return .falló(error.localizedDescription)
            }
        }

        var texto: String
        var origen: String

        let diagnostico = diagnosticar(video)
        if let error = diagnostico.error, diagnostico.pistas.isEmpty {
            return .falló(error)
        }

        let pista = opciones.pistaPreferida.flatMap { indice in
            diagnostico.pistas.first { $0.indice == indice }
        } ?? diagnostico.elegida

        // Si el usuario eligió la pista a mano, manda él.
        let latino = opciones.usarRed && opciones.preferirLatino && diagnostico.esEpisodio
            && opciones.pistaPreferida == nil && pista?.esLatino != true
            ? await Addic7ed.buscarLatino(para: video) : nil

        if let latino {
            texto = latino.texto
            origen = latino.explicacion
        } else if let pista {
            let temporal = FileManager.default.temporaryDirectory
                .appendingPathComponent("subfix-\(UUID().uuidString).srt")
            defer { try? FileManager.default.removeItem(at: temporal) }
            do {
                try Sondeo.extraer(pista: pista, de: video, a: temporal)
                texto = try TextoSRT.leer(temporal).texto
                origen = "pista \(pista.resumen)"
            } catch {
                return .falló(error.localizedDescription)
            }
        } else if let suelto = diagnostico.suelto ?? sueltoPara(video) {
            do {
                let leido = try TextoSRT.leer(suelto)
                texto = leido.texto
                origen = "\(suelto.lastPathComponent) (\(leido.codificacion))"
            } catch {
                return .falló(error.localizedDescription)
            }
        } else if opciones.usarRed, let hallazgo = await OpenSubtitles.buscar(para: video) {
            texto = hallazgo.texto
            origen = hallazgo.explicacion
        } else {
            return .sinSubtitulos(soloImagen: !diagnostico.pistasDeImagen.isEmpty)
        }

        let sinEtiquetas = TextoSRT.quitarEtiquetasASS(texto)
        let depurado = TextoSRT.depurarCaracteres(sinEtiquetas.texto)
        let limpio = TextoSRT.quitarPublicidad(depurado.texto)
        do {
            if FileManager.default.fileExists(atPath: destino.path) {
                try TextoSRT.apartar(destino)
            }
            try TextoSRT.escribirParaElTV(limpio.texto, en: destino)
        } catch {
            return .falló(error.localizedDescription)
        }
        let lineas = limpio.texto.components(separatedBy: "\n").count
        return .listo(origen: origen, lineas: lineas, publicidadQuitada: limpio.quitados,
                      etiquetasLimpiadas: sinEtiquetas.tocadas, caracteresDepurados: depurado.tocadas)
    }

    // MARK: - Archivos

    /// «Ted.Lasso.S01E01.HDR.2160p….mkv» → «Ted Lasso S01E01». Nil si no es un capítulo.
    public static func carpetaDeCapitulo(para video: URL) -> String? {
        let nombre = video.deletingPathExtension().lastPathComponent
        guard let marca = nombre.range(of: "[Ss](\\d{1,2})[\\s._-]?[Ee](\\d{1,3})",
                                       options: .regularExpression) else { return nil }
        let (_, temporada, episodio) = OpenSubtitles.tituloLimpio(video)
        guard let temporada, let episodio else { return nil }

        let serie = String(nombre[..<marca.lowerBound])
            .replacingOccurrences(of: "[._\\[\\]()-]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let codigo = String(format: "S%02dE%02d", temporada, episodio)
        return serie.isEmpty ? codigo : "\(serie) \(codigo)"
    }

    /// Mete el capítulo y su .srt en una subcarpeta propia, junto a donde estaban.
    /// Mover dentro del mismo disco es renombrar: no copia los gigas. Nunca pisa
    /// nada; si el destino ya existe, lo deja todo como estaba.
    @discardableResult
    public static func organizarPorCapitulo(_ video: URL) throws -> URL {
        guard let nombre = carpetaDeCapitulo(para: video) else { return video }
        let actual = video.deletingLastPathComponent()
        guard actual.lastPathComponent != nombre else { return video }   // ya estaba

        let carpeta = actual.appendingPathComponent(nombre, isDirectory: true)
        let gestor = FileManager.default
        try gestor.createDirectory(at: carpeta, withIntermediateDirectories: true)

        let base = video.deletingPathExtension().lastPathComponent
        let acompañantes = ((try? gestor.contentsOfDirectory(atPath: actual.path)) ?? [])
            .filter { $0.hasPrefix(base + ".") && !$0.hasPrefix("._")
                      && $0 != video.lastPathComponent
                      && ($0.hasSuffix(".srt") || $0.contains(".srt.anterior")) }
            .map { actual.appendingPathComponent($0) }

        for archivo in [video] + acompañantes {
            let destino = carpeta.appendingPathComponent(archivo.lastPathComponent)
            if gestor.fileExists(atPath: destino.path) {
                throw ErrorDeSubFix.yaExiste(destino.lastPathComponent)
            }
        }
        for archivo in [video] + acompañantes {
            try gestor.moveItem(at: archivo, to: carpeta.appendingPathComponent(archivo.lastPathComponent))
        }
        return carpeta.appendingPathComponent(video.lastPathComponent)
    }

    /// El .srt debe llamarse exactamente como el video: un «pelicula.es.srt» el
    /// TV lo trata como archivo ajeno y no lo ofrece.
    public static func destinoSRT(de video: URL) -> URL {
        video.deletingPathExtension().appendingPathExtension("srt")
    }

    /// Un suelto que no lleve el nombre del video sólo se acepta si el video es
    /// el único de la carpeta; con varias películas juntas, adivinar significa
    /// ponerle a una los diálogos de otra.
    public static func sueltoPara(_ video: URL) -> URL? {
        let carpeta = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent
        let destino = destinoSRT(de: video)
        let gestor = FileManager.default

        let videosEnCarpeta = (try? gestor.contentsOfDirectory(atPath: carpeta.path))?
            .filter { extensionesDeVideo.contains(($0 as NSString).pathExtension.lowercased())
                      && !$0.hasPrefix("._") }.count ?? 1

        var candidatos: [URL] = []
        for nombreCarpeta in ["", "Subs", "subs", "Subtitles", "Subtítulos"] {
            let raiz = nombreCarpeta.isEmpty ? carpeta : carpeta.appendingPathComponent(nombreCarpeta)
            guard let archivos = try? gestor.contentsOfDirectory(atPath: raiz.path) else { continue }
            for archivo in archivos.sorted() where !archivo.hasPrefix("._") {
                guard extensionesDeSubtitulo.contains((archivo as NSString).pathExtension.lowercased())
                else { continue }
                let ruta = raiz.appendingPathComponent(archivo)
                if ruta.path != destino.path { candidatos.append(ruta) }
            }
        }
        guard !candidatos.isEmpty else { return nil }

        let propios = candidatos.filter { $0.lastPathComponent.hasPrefix(base) }
        if propios.isEmpty, videosEnCarpeta > 1 { return nil }

        let grupo = propios.isEmpty ? candidatos : propios
        let españoles = grupo.filter {
            $0.lastPathComponent.range(of: "\\b(spa|es|esp|spanish|latin|castellano)\\b",
                                       options: [.regularExpression, .caseInsensitive]) != nil
        }
        return (españoles.isEmpty ? grupo : españoles).first
    }

    /// Recoge los videos de lo que se suelte en la ventana: archivos sueltos o
    /// carpetas enteras. Los ._archivo de macOS en exFAT son metadatos, no videos.
    public static func videos(en rutas: [URL]) -> [URL] {
        var encontrados: [URL] = []
        let gestor = FileManager.default

        for ruta in rutas {
            var esCarpeta: ObjCBool = false
            guard gestor.fileExists(atPath: ruta.path, isDirectory: &esCarpeta) else { continue }

            if esCarpeta.boolValue {
                let enumerador = gestor.enumerator(at: ruta,
                                                   includingPropertiesForKeys: [.isRegularFileKey],
                                                   options: [.skipsHiddenFiles])
                while let elemento = enumerador?.nextObject() as? URL {
                    if esVideo(elemento) { encontrados.append(elemento) }
                }
            } else if esVideo(ruta) {
                encontrados.append(ruta)
            }
        }
        return encontrados.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func esVideo(_ url: URL) -> Bool {
        extensionesDeVideo.contains(url.pathExtension.lowercased())
            && !url.lastPathComponent.hasPrefix("._")
    }

    /// En discos exFAT macOS deja archivos fantasma ._nombre; dot_clean los funde.
    public static func limpiarFantasmas(en carpetas: Set<URL>) {
        guard let salida = try? Herramientas.correr("mount", []) else { return }
        let exfat = salida.texto.components(separatedBy: "\n").compactMap { linea -> String? in
            guard linea.contains("(exfat") || linea.contains("(msdos"),
                  let inicio = linea.range(of: " on "),
                  let fin = linea.range(of: " (", range: inicio.upperBound..<linea.endIndex)
            else { return nil }
            return String(linea[inicio.upperBound..<fin.lowerBound])
        }
        for carpeta in carpetas where exfat.contains(where: { carpeta.path.hasPrefix($0) }) {
            _ = try? Herramientas.correr("dot_clean", ["-m", carpeta.path])
        }
    }
}
