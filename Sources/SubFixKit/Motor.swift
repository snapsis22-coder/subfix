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
            if srtExistente != nil {
                if !srtEsEspañol { return "El .srt que tiene NO es español: se apartará y se buscará otro" }
                return srtBienFormado ? "Ya tiene subtítulo en español" : "Reparar el .srt existente"
            }
            if let elegida { return "Extraer \(elegida.codec) · \(elegida.idioma ?? "?")" }
            if let suelto { return "Usar \(suelto.lastPathComponent)" }
            if !pistasDeImagen.isEmpty { return "Sólo imagen — buscar en OpenSubtitles" }
            return "Sin subtítulos — buscar en OpenSubtitles"
        }

        /// El subtítulo latino que el video trae DENTRO (sin forzados ni para sordos).
        public var latinoIntegrado: Pista? { pistas.first { $0.esLatino && !$0.descartable } }
        /// Uno en español dentro del video, latino o no.
        public var españolIntegrado: Pista? { pistas.first { ($0.esEspañol || $0.esLatino) && !$0.descartable } }

        /// Si ya no hay nada que hacer, el porqué (la fila sale como «Lista» y no se busca nada).
        /// nil = todavía hay trabajo.
        public func yaListo(preferirLatino: Bool, extraerDelArchivo: Bool) -> String? {
            if error != nil { return nil }
            if srtExistente != nil {
                guard srtEsEspañol, srtBienFormado, !(srtDeEspaña && preferirLatino) else { return nil }
                if latinoIntegrado != nil { return "Trae el latino dentro y además un .srt aparte" }
                return srtDeEspaña ? "Tiene el subtítulo en español en un .srt aparte, al lado del video"
                                   : "Tiene el subtítulo latino en un .srt aparte, al lado del video"
            }
            guard !extraerDelArchivo else { return nil }
            if latinoIntegrado != nil { return "Ya trae el subtítulo latino dentro del video" }
            if !preferirLatino, españolIntegrado != nil { return "Ya trae subtítulo en español dentro del video" }
            return nil
        }

        /// Lo mismo que `plan`, contando con que se busque latino para las series.
        public func plan(preferirLatino: Bool, extraerDelArchivo: Bool = true, pistaManual: Bool = false) -> String {
            if !pistaManual, let listo = yaListo(preferirLatino: preferirLatino, extraerDelArchivo: extraerDelArchivo) {
                return listo
            }
            if srtExistente != nil, srtEsEspañol, srtDeEspaña, preferirLatino {
                return "El .srt de al lado es de España: con «Subdivx» buscas el latino"
            }
            if !extraerDelArchivo, !pistaManual, srtExistente == nil {
                if españolIntegrado != nil {
                    return "Trae subtítulo en español dentro, pero no dice si es latino: se buscará el latino en la web"
                }
                return "No tiene subtítulo en español: «Buscar subtítulos» lo busca en la web"
            }
            if !pistaManual, srtExistente == nil, latinoIntegrado != nil {
                return "Trae el latino dentro del video: se copiará a un .srt aparte"
            }
            guard preferirLatino, esEpisodio, error == nil, srtExistente == nil,
                  elegida?.esLatino != true else { return plan }
            if let elegida { return "Buscar latino en Addic7ed · si no hay, \(elegida.codec) · \(elegida.idioma ?? "?")" }
            return "Buscar latino en Addic7ed"
        }

        public var esEpisodio: Bool { carpeta != nil }
        /// «Ted Lasso S01E01» si el archivo es un capítulo de serie.
        public let carpeta: String?
        /// Del .srt que ya está junto al video: si es español de verdad y si es de España.
        public internal(set) var srtEsEspañol = true
        public internal(set) var srtDeEspaña = false

        public var necesitaRed: Bool {
            srtExistente == nil && elegida == nil && suelto == nil
        }
    }

    public static func diagnosticar(_ video: URL) -> Diagnostico {
        var diagnostico = diagnosticarPistas(video)
        if let existente = diagnostico.srtExistente, let texto = try? TextoSRT.leer(existente).texto {
            diagnostico.srtEsEspañol = TextoSRT.pareceEspañol(texto)
            diagnostico.srtDeEspaña = TextoSRT.pareceDeEspaña(texto)
        }
        return diagnostico
    }

    private static func diagnosticarPistas(_ video: URL) -> Diagnostico {
        let destino = destinoSRT(de: video)
        let existente = FileManager.default.fileExists(atPath: destino.path) ? destino : nil
        let carpeta = carpetaDeCapitulo(para: video)

        do {
            let pistas = try Sondeo.pistas(de: video)
            let deTexto = pistas.filter(\.esTexto)
            // Si no hay ninguna marcada en español, sólo valen las que no dicen idioma
            // (pueden serlo); una marcada «eng» o «fre» nunca se toma por español.
            let sinIdioma = deTexto.filter { ($0.idioma ?? "und").isEmpty || ($0.idioma ?? "und") == "und" }
            let candidatas = deTexto.filter(\.esEspañol).isEmpty ? sinIdioma : deTexto.filter(\.esEspañol)
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
                   caracteresDepurados: Int, deEspaña: Bool)
        case reparado(codificacionAnterior: String, deEspaña: Bool)
        case yaEstaba(deEspaña: Bool)
        case sinSubtitulos(soloImagen: Bool)
        /// Sólo apareció el de España y se pidió latino: queda apartado en `candidato`
        /// (un temporal) y NO se pone junto a la película hasta que el usuario lo acepte.
        case soloEspaña(origen: String, candidato: URL)
        /// Se encontró subtítulo, pero ninguno va con este video (otra versión, otro montaje).
        case desfasado(String)
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
        /// Sacar el subtítulo de una pista del archivo (o del .srt suelto). Apagado,
        /// sólo se busca en la web; una pista elegida a mano (`pistaPreferida`) manda.
        public var extraerDelArchivo: Bool
        /// Si lo único que hay es de España, no instalarlo: devolver `.soloEspaña`.
        public var retenerEspaña: Bool
        /// Comparar lo bajado con el video (`Sincronia`) y quedarse con el que va sincronizado.
        public var comprobarSincronia: Bool
        /// Huellas (`Sincronia.huella`) de subtítulos que el usuario ya rechazó con «Reprocesar».
        public var descartados: Set<String>

        public init(usarRed: Bool = true, forzar: Bool = false, pistaPreferida: Int? = nil,
                    preferirLatino: Bool = false, extraerDelArchivo: Bool = true, retenerEspaña: Bool = false,
                    comprobarSincronia: Bool = true, descartados: Set<String> = []) {
            self.comprobarSincronia = comprobarSincronia
            self.descartados = descartados
            self.extraerDelArchivo = extraerDelArchivo
            self.retenerEspaña = retenerEspaña
            self.usarRed = usarRed
            self.forzar = forzar
            self.pistaPreferida = pistaPreferida
            self.preferirLatino = preferirLatino
        }
    }

    /// Botón «Extraer latino»: sólo saca el subtítulo del propio archivo (el latino primero),
    /// lo limpia y lo deja como .srt junto al video. Sin internet. Reemplaza el .srt que hubiera
    /// (apartándolo como «.anterior»); el de España no se pone sin permiso.
    public static let extraerLatino = Opciones(usarRed: false, forzar: true, preferirLatino: true,
                                               extraerDelArchivo: true, retenerEspaña: true)

    public static func procesar(_ video: URL, opciones: Opciones = Opciones()) async -> Resultado {
        let destino = destinoSRT(de: video)

        // Existir no basta: los .srt que vienen con el torrent suelen estar en
        // Latin-1 y sin CRLF, que es justo lo que el TV pinta como basura.
        // Uno que ni siquiera es español (un francés que se coló) no cuenta como
        // puesto: se aparta como «.anterior» y se busca otro.
        if FileManager.default.fileExists(atPath: destino.path), !opciones.forzar,
           let texto = try? TextoSRT.leer(destino).texto, !TextoSRT.pareceEspañol(texto) {
            do { try TextoSRT.apartar(destino) } catch { return .falló(error.localizedDescription) }
        }
        if FileManager.default.fileExists(atPath: destino.path), !opciones.forzar {
            if TextoSRT.estaBienFormado(destino) {
                let texto = (try? TextoSRT.leer(destino).texto) ?? ""
                return .yaEstaba(deEspaña: TextoSRT.pareceDeEspaña(texto))
            }
            do {
                let (texto, codificacion) = try TextoSRT.leer(destino)
                try TextoSRT.apartar(destino)
                try TextoSRT.escribirParaElTV(TextoSRT.depurarCaracteres(texto).texto, en: destino)
                return .reparado(codificacionAnterior: codificacion, deEspaña: TextoSRT.pareceDeEspaña(texto))
            } catch {
                return .falló(error.localizedDescription)
            }
        }

        let diagnostico = diagnosticar(video)
        if let error = diagnostico.error, diagnostico.pistas.isEmpty {
            return .falló(error)
        }

        let delArchivo = opciones.extraerDelArchivo || opciones.pistaPreferida != nil

        // Ya trae el subtítulo dentro y no se pidió sacarlo: no hay nada que buscar.
        if !delArchivo, !opciones.forzar,
           diagnostico.yaListo(preferirLatino: opciones.preferirLatino, extraerDelArchivo: false) != nil {
            return .yaEstaba(deEspaña: false)
        }
        let pista = delArchivo ? (opciones.pistaPreferida.flatMap { indice in
            diagnostico.pistas.first { $0.indice == indice }
        } ?? diagnostico.elegida) : nil

        // Si el usuario eligió la pista a mano, manda él: ni se compara ni se busca otra.
        if let elegida = opciones.pistaPreferida.flatMap({ indice in diagnostico.pistas.first { $0.indice == indice } }) {
            let temporal = FileManager.default.temporaryDirectory
                .appendingPathComponent("subfix-\(UUID().uuidString).srt")
            defer { try? FileManager.default.removeItem(at: temporal) }
            do {
                try Sondeo.extraer(pista: elegida, de: video, a: temporal)
                let texto = try TextoSRT.leer(temporal).texto
                return instalar(texto, origen: "pista \(elegida.resumen)", en: destino, retenerEspaña: opciones.retenerEspaña)
            } catch {
                return .falló(error.localizedDescription)
            }
        }

        var eleccion = Eleccion(opciones: opciones,
                                comprobador: opciones.comprobarSincronia ? Sincronia.Comprobador(video: video) : nil)

        let latino = opciones.usarRed && (opciones.preferirLatino || !delArchivo) && diagnostico.esEpisodio
            && pista?.esLatino != true
        if latino {
            await Addic7ed.candidatosLatinos(para: video) { hallazgo in
                eleccion.considerar(hallazgo.texto, origen: hallazgo.explicacion)
            }
        }

        // Lo que trae el archivo va sincronizado por definición: no se compara.
        if !eleccion.terminada, let pista {
            let temporal = FileManager.default.temporaryDirectory
                .appendingPathComponent("subfix-\(UUID().uuidString).srt")
            defer { try? FileManager.default.removeItem(at: temporal) }
            do {
                try Sondeo.extraer(pista: pista, de: video, a: temporal)
                let texto = try TextoSRT.leer(temporal).texto
                // Una pista elegida sola tiene que ser español de verdad (sin idioma marcado puede ser inglés).
                if TextoSRT.pareceEspañol(texto) {
                    _ = eleccion.considerar(texto, origen: "pista \(pista.resumen)", comprobar: false)
                }
            } catch {
                if eleccion.vacia { return .falló(error.localizedDescription) }
            }
        }

        // Un .srt suelto del torrent: suele ir con el video, pero se comprueba.
        if !eleccion.terminada, delArchivo, let suelto = diagnostico.suelto ?? sueltoPara(video) {
            do {
                let leido = try TextoSRT.leer(suelto)
                if TextoSRT.pareceEspañol(leido.texto) {
                    _ = eleccion.considerar(leido.texto, origen: "\(suelto.lastPathComponent) (\(leido.codificacion))")
                }
            } catch {
                if eleccion.vacia { return .falló(error.localizedDescription) }
            }
        }

        if !eleccion.terminada, opciones.usarRed {
            await OpenSubtitles.candidatos(para: video, preferirLatino: opciones.preferirLatino) { hallazgo in
                eleccion.considerar(hallazgo.texto, origen: hallazgo.explicacion)
            }
        }

        return eleccion.resultado(en: destino, retenerEspaña: opciones.retenerEspaña,
                                  soloImagen: !diagnostico.pistasDeImagen.isEmpty)
    }

    /// Entre todo lo encontrado, el mejor: latino antes que de España (si se pidió latino)
    /// y, dentro de eso, sincronizado antes que corregido antes que sin comprobar. Lo que no
    /// va con el video no se instala nunca. Lo que el usuario ya rechazó, tampoco.
    struct Eleccion {
        let opciones: Opciones
        let comprobador: Sincronia.Comprobador?
        private(set) var mejor: (texto: String, origen: String, puntos: Int)?
        private(set) var desfasados: [String] = []
        private(set) var terminada = false
        var vacia: Bool { mejor == nil }

        init(opciones: Opciones, comprobador: Sincronia.Comprobador?) {
            self.opciones = opciones
            self.comprobador = comprobador
        }

        /// `true` = ya está el ideal, no hace falta bajar más.
        @discardableResult
        mutating func considerar(_ texto: String, origen: String, comprobar: Bool = true) -> Bool {
            guard !terminada else { return true }
            if opciones.descartados.contains(Motor.huella(texto)) { return false }
            let latino = !opciones.preferirLatino || !TextoSRT.pareceDeEspaña(texto)
            var final = texto, nota = "", rango = 3
            if comprobar, let comprobador {
                let veredicto = comprobador.comprobar(texto)
                switch veredicto {
                case .desfasado:
                    desfasados.append(origen)
                    return false
                case .corregible(let ajuste, _):
                    final = Sincronia.aplicar(ajuste, a: texto)
                    // El mismo que ya se corrigió una vez y el usuario rechazó.
                    if opciones.descartados.contains(Motor.huella(final)) { return false }
                case .sincronizado, .sinComprobar:
                    break
                }
                rango = veredicto.rango
                nota = " · " + veredicto.resumen
            }
            let puntos = (latino ? 10 : 0) + rango
            if puntos > (mejor?.puntos ?? -1) { mejor = (final, origen + nota, puntos) }
            // Sin nada con qué comparar no tiene sentido seguir bajando: vale el primero latino.
            terminada = latino && (rango == 3 || comprobador?.sinReferencia == true)
            return terminada
        }

        func resultado(en destino: URL, retenerEspaña: Bool, soloImagen: Bool) -> Resultado {
            if let mejor { return Motor.instalar(mejor.texto, origen: mejor.origen, en: destino, retenerEspaña: retenerEspaña) }
            if !desfasados.isEmpty { return .desfasado(desfasados.joined(separator: ", ")) }
            return .sinSubtitulos(soloImagen: soloImagen)
        }
    }

    /// Huella de un subtítulo tal como queda instalado (limpio): así se reconoce el que
    /// el usuario rechazó aunque vuelva a llegar crudo, con publicidad o etiquetas.
    public static func huella(_ texto: String) -> String {
        let limpio = TextoSRT.quitarPublicidad(
            TextoSRT.depurarCaracteres(TextoSRT.quitarEtiquetasASS(texto).texto).texto).texto
        return Sincronia.huella(limpio)
    }

    /// Limpia el texto y lo deja junto al video con el formato que el TV entiende.
    /// Lo que hubiera antes se aparta como «.anterior», nunca se pisa.
    static func instalar(_ texto: String, origen: String, en destino: URL,
                                 retenerEspaña: Bool = false) -> Resultado {
        let sinEtiquetas = TextoSRT.quitarEtiquetasASS(texto)
        let depurado = TextoSRT.depurarCaracteres(sinEtiquetas.texto)
        let limpio = TextoSRT.quitarPublicidad(depurado.texto)
        if retenerEspaña, TextoSRT.pareceDeEspaña(limpio.texto) {
            // Se aparta ya limpio, con el nombre que llevaría: aceptarlo es sólo instalar este archivo.
            let carpeta = FileManager.default.temporaryDirectory
                .appendingPathComponent("subfix-espana-\(UUID().uuidString)")
            let candidato = carpeta.appendingPathComponent(destino.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
                try TextoSRT.escribirParaElTV(limpio.texto, en: candidato)
            } catch {
                return .falló(error.localizedDescription)
            }
            return .soloEspaña(origen: origen, candidato: candidato)
        }
        let lineas = limpio.texto.components(separatedBy: "\n").count
        // Ya estaba exactamente así (p. ej. el botón pulsado dos veces): no se aparta nada.
        let normal = { (t: String) in
            t.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let actual = try? TextoSRT.leer(destino).texto, normal(actual) == normal(limpio.texto) {
            return .listo(origen: origen, lineas: lineas, publicidadQuitada: limpio.quitados,
                          etiquetasLimpiadas: sinEtiquetas.tocadas, caracteresDepurados: depurado.tocadas,
                          deEspaña: TextoSRT.pareceDeEspaña(limpio.texto))
        }
        do {
            if FileManager.default.fileExists(atPath: destino.path) {
                try TextoSRT.apartar(destino)
            }
            try TextoSRT.escribirParaElTV(limpio.texto, en: destino)
        } catch {
            return .falló(error.localizedDescription)
        }
        return .listo(origen: origen, lineas: lineas, publicidadQuitada: limpio.quitados,
                      etiquetasLimpiadas: sinEtiquetas.tocadas, caracteresDepurados: depurado.tocadas,
                      deEspaña: TextoSRT.pareceDeEspaña(limpio.texto))
    }

    // MARK: - Subtítulos traídos a mano (Subdivx)

    /// Instala un .srt que el usuario bajó por su cuenta. Lo pidió él, así que
    /// reemplaza lo que hubiera (apartándolo).
    public static func adoptar(_ subtitulo: URL, para video: URL, retenerEspaña: Bool = false) -> Resultado {
        do {
            let (texto, codificacion) = try TextoSRT.leer(subtitulo)
            // Lo bajado puede ser un aviso del sitio con extensión .srt («No se pudo extraer
            // el archivo. Error técnico.», 46 bytes): eso jamás se pone junto al video.
            guard TextoSRT.esSRT(texto) else {
                return .falló("«\(subtitulo.lastPathComponent)» no es un subtítulo de verdad")
            }
            return instalar(texto, origen: "\(subtitulo.lastPathComponent) (\(codificacion))",
                            en: destinoSRT(de: video), retenerEspaña: retenerEspaña)
        } catch {
            return .falló(error.localizedDescription)
        }
    }

    /// Lo bajado de Subdivx (o soltado a mano) para UN video: de todos sus .srt se queda
    /// con el que va sincronizado (y latino, si se pidió). Un paquete de Subdivx suele
    /// traer varias versiones: la de WEB-DL y la de BluRay no van igual.
    public static func adoptarComprobando(_ subtitulos: [URL], para video: URL, preferirLatino: Bool,
                                          descartados: Set<String> = [], comprobar: Bool = true) -> Resultado {
        var opciones = Opciones(preferirLatino: preferirLatino, retenerEspaña: preferirLatino,
                                comprobarSincronia: comprobar, descartados: descartados)
        opciones.forzar = true
        var eleccion = Eleccion(opciones: opciones, comprobador: comprobar ? Sincronia.Comprobador(video: video) : nil)
        var vistos = 0, problema: String?
        for subtitulo in subtitulos {
            do {
                let (texto, codificacion) = try TextoSRT.leer(subtitulo)
                // Lo bajado puede ser un aviso del sitio con extensión .srt: eso no compite.
                guard TextoSRT.esSRT(texto), TextoSRT.pareceEspañol(texto) else { continue }
                vistos += 1
                if eleccion.considerar(texto, origen: "\(subtitulo.lastPathComponent) (\(codificacion))") { break }
            } catch {
                problema = error.localizedDescription
            }
        }
        if vistos == 0 {
            return .falló(problema ?? "«\(subtitulos.first?.lastPathComponent ?? "lo bajado")» no traía un subtítulo en español")
        }
        if eleccion.vacia, opciones.descartados.count > 0, eleccion.desfasados.isEmpty {
            return .falló("es el mismo subtítulo que ya habías descartado")
        }
        return eleccion.resultado(en: destinoSRT(de: video), retenerEspaña: preferirLatino, soloImagen: false)
    }

    static let extensionesDeArchivo: Set<String> = ["zip", "rar", "7z"]

    /// Los .srt que hay en lo que se soltó: sueltos, dentro de un .zip/.rar (se
    /// abre con el bsdtar del sistema, que lee RAR) o en una carpeta SIN videos,
    /// como la que deja el Finder al descomprimir. Una carpeta con videos es la
    /// de la serie, y sus .srt son los que ya están puestos.
    public static func subtitulos(en rutas: [URL]) -> [URL] {
        let gestor = FileManager.default
        var encontrados: [URL] = []

        func srtsDentro(de carpeta: URL) -> [URL] {
            let enumerador = gestor.enumerator(at: carpeta, includingPropertiesForKeys: nil,
                                               options: [.skipsHiddenFiles])
            var srts: [URL] = []
            while let elemento = enumerador?.nextObject() as? URL {
                if elemento.pathExtension.lowercased() == "srt", !elemento.lastPathComponent.hasPrefix("._") {
                    srts.append(elemento)
                }
            }
            return srts
        }

        for ruta in rutas {
            var esCarpeta: ObjCBool = false
            guard gestor.fileExists(atPath: ruta.path, isDirectory: &esCarpeta) else { continue }
            let ext = ruta.pathExtension.lowercased()
            if esCarpeta.boolValue {
                if videos(en: [ruta]).isEmpty { encontrados += srtsDentro(de: ruta) }
            } else if ext == "srt" {
                encontrados.append(ruta)
            } else if extensionesDeArchivo.contains(ext) {
                // Los .zip de Subdivx guardan los nombres en la página de códigos de DOS
                // («Espa\u{A4}ol»): APFS los rechaza como UTF-8 inválido y no sale nada.
                // Si el intento normal falla, se repite leyéndolos como CP850.
                for opciones in [[], ["--options", "hdrcharset=CP850"]] {
                    let temporal = gestor.temporaryDirectory.appendingPathComponent("subfix-\(UUID().uuidString)")
                    guard (try? gestor.createDirectory(at: temporal, withIntermediateDirectories: true)) != nil,
                          let salida = try? Herramientas.correr("bsdtar", opciones + ["-xf", ruta.path, "-C", temporal.path])
                    else { continue }
                    let srts = srtsDentro(de: temporal)
                    if salida.codigo == 0, !srts.isEmpty { encontrados += srts; break }
                }
            }
        }
        return encontrados
    }

    /// A cada video, el subtítulo que le corresponde. Un capítulo se empareja por
    /// SxxEyy; si sólo hay un video en juego, se lleva lo que haya. Entre varios
    /// candidatos (Subdivx suele traer el de España y el latino juntos) gana el
    /// que no tiene vosotros y, a igualdad, el que dice «latin» en el nombre.
    public static func emparejar(_ subtitulos: [URL], con videos: [URL]) -> [(video: URL, subtitulo: URL)] {
        repartir(subtitulos, con: videos).compactMap { par in par.subtitulos.first.map { (par.video, $0) } }
    }

    /// Como `emparejar`, pero con TODOS los candidatos de cada video, del mejor al peor,
    /// para poder probar su sincronía uno por uno.
    public static func repartir(_ subtitulos: [URL], con videos: [URL]) -> [(video: URL, subtitulos: [URL])] {
        func codigo(_ url: URL) -> String? {
            let (_, t, e) = OpenSubtitles.tituloLimpio(url)
            guard let t, let e else { return nil }
            return "\(t)x\(e)"
        }
        var puntajes: [URL: Int] = [:]
        func puntaje(_ srt: URL) -> Int {
            if let ya = puntajes[srt] { return ya }
            let texto = (try? TextoSRT.leer(srt).texto) ?? ""
            var n = 0
            // Si no es un .srt de verdad o no es español, no compite: antes un francés
            // le ganaba al de España, y un aviso de error del sitio pasaba por subtítulo.
            if TextoSRT.esSRT(texto), TextoSRT.pareceEspañol(texto) {
                if !TextoSRT.pareceDeEspaña(texto) { n += 10 }
                n += 5
                if srt.lastPathComponent.range(of: "latin", options: .caseInsensitive) != nil { n += 2 }
            } else {
                n = -1
            }
            puntajes[srt] = n
            return n
        }

        var pares: [(video: URL, subtitulos: [URL])] = []
        for video in videos {
            let candidatos: [URL]
            if let suyo = codigo(video) {
                let mismos = subtitulos.filter { codigo($0) == suyo }
                candidatos = mismos.isEmpty && videos.count == 1 ? subtitulos : mismos
            } else {
                candidatos = videos.count == 1 ? subtitulos : []
            }
            let validos = candidatos.filter { puntaje($0) >= 0 }.sorted { puntaje($0) > puntaje($1) }
            if !validos.isEmpty { pares.append((video, validos)) }
        }
        return pares
    }

    /// Lo que conviene escribir en el buscador de Subdivx: «Ted Lasso S01E02»
    /// para un capítulo, el título para una película.
    public static func busquedaSubdivx(para video: URL) -> String {
        if let capitulo = carpetaDeCapitulo(para: video) { return capitulo }
        return OpenSubtitles.tituloLimpio(video).titulo.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
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
            .filter { nombre in
                guard !nombre.hasPrefix("._"), nombre != video.lastPathComponent else { return false }
                // El .srt y lo apartado, y también el MKV que SubFix creó al lado.
                return (nombre.hasPrefix(base + ".") && (nombre.hasSuffix(".srt") || nombre.contains(".srt.anterior")))
                    || (nombre.hasPrefix(base + " (SubFix") && nombre.hasSuffix(".mkv"))
            }
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
