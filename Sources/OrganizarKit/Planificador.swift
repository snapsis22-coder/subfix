import Foundation

/// Las dos bibliotecas a donde va todo.
public struct Bibliotecas: Equatable, Sendable {
    public var peliculas: URL
    public var series: URL

    public init(peliculas: URL, series: URL) {
        self.peliculas = peliculas
        self.series = series
    }
}

/// Un archivo o carpeta que hay que llevar de un sitio a otro.
public struct Movimiento: Equatable, Sendable {
    public let desde: URL
    public let hacia: URL
}

/// Cómo viene una descarga: suelta, en una carpeta propia o como temporada entera.
public enum Forma: Equatable, Sendable {
    /// Un video suelto y lo que va pegado a su nombre (`.srt`, `.nfo`…).
    case archivo(video: URL, acompañantes: [URL])
    /// Una carpeta con un solo video: se mueve la carpeta entera, con todo lo de dentro.
    case carpeta(videos: [URL])
}

/// Lo que se averigua de una descarga antes de tocarla.
public struct Examen: Equatable, Sendable {
    public let origen: URL
    public let forma: Forma
    public let lectura: Lectura?

    public init(origen: URL, forma: Forma, lectura: Lectura?) {
        self.origen = origen
        self.forma = forma
        self.lectura = lectura
    }
}

public enum Planificador {

    // MARK: - Examinar

    /// Mira una descarga y dice qué es. Devuelve nil si no hay ningún video dentro.
    public static func examinar(_ origen: URL) -> Examen? {
        var esCarpeta: ObjCBool = false
        guard FileManager.default.fileExists(atPath: origen.path, isDirectory: &esCarpeta) else { return nil }

        if !esCarpeta.boolValue {
            guard Analizador.esVideo(origen) else { return nil }
            return Examen(origen: origen,
                          forma: .archivo(video: origen, acompañantes: acompañantes(de: origen)),
                          lectura: Analizador.leer(origen.lastPathComponent))
        }

        let videos = videosDentro(de: origen)
        guard !videos.isEmpty else { return nil }
        return Examen(origen: origen, forma: .carpeta(videos: videos),
                      lectura: leerCarpeta(origen, videos: videos))
    }

    /// Lo que hay en la carpeta de entrada, ya examinado. Lo oculto y lo que no lleva
    /// video (un `.srt` suelto, un instalador) se ignora.
    public static func examinarCarpeta(_ carpeta: URL) -> [Examen] {
        let contenido = (try? FileManager.default.contentsOfDirectory(
            at: carpeta, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return contenido
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap(examinar)
    }

    /// Una carpeta con un solo video se lee por el nombre de la carpeta si trae año
    /// (suele estar más limpio), salvo que el video diga que es un episodio.
    static func leerCarpeta(_ carpeta: URL, videos: [URL]) -> Lectura? {
        let porCarpeta = Analizador.leer(carpeta.lastPathComponent)

        if videos.count == 1 {
            let porVideo = Analizador.leer(videos[0].lastPathComponent)
            if case .serie? = porVideo { return porVideo }
            if case .pelicula(_, let año)? = porCarpeta, año != nil { return porCarpeta }
            return porVideo ?? porCarpeta
        }

        // Varios videos: es una temporada si todos son episodios de la misma.
        let lecturas = videos.map { Analizador.leer($0.lastPathComponent) }
        if case .serie(let nombre, let temporada, _)? = lecturas.first,
           lecturas.allSatisfy({
               if case .serie(let n, let t, _)? = $0 { return n == nombre && t == temporada }
               return false
           }) {
            return .serie(nombre: nombre, temporada: temporada, episodio: nil)
        }
        if case .serie(let nombre, let temporada, _)? = porCarpeta {
            return .serie(nombre: nombre, temporada: temporada, episodio: nil)
        }
        return porCarpeta
    }

    /// Los archivos que comparten nombre con el video: `peli.srt`, `peli.es.srt`, `peli.nfo`.
    static func acompañantes(de video: URL) -> [URL] {
        let raiz = video.deletingPathExtension().lastPathComponent + "."
        let vecinos = (try? FileManager.default.contentsOfDirectory(
            at: video.deletingLastPathComponent(), includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return vecinos.filter {
            $0 != video && !Analizador.esVideo($0) && $0.lastPathComponent.hasPrefix(raiz)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Los videos de una carpeta, sin las muestras de 1 minuto que traen algunas descargas.
    static func videosDentro(de carpeta: URL) -> [URL] {
        guard let recorrido = FileManager.default.enumerator(
            at: carpeta, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
        var videos: [URL] = []
        for case let url as URL in recorrido where Analizador.esVideo(url) {
            let tamaño = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let esMuestra = url.lastPathComponent.lowercased().contains("sample") && tamaño < 300_000_000
            if !esMuestra { videos.append(url) }
        }
        return videos.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Planear

    /// A dónde va cada pieza. No toca el disco.
    public static func movimientos(_ examen: Examen, como lectura: Lectura,
                                   en bibliotecas: Bibliotecas) -> [Movimiento] {
        let destino: URL
        switch lectura {
        case .pelicula:
            destino = bibliotecas.peliculas.appendingPathComponent(lectura.carpeta)
        case .serie:
            destino = bibliotecas.series.appendingPathComponent(lectura.carpeta)
                .appendingPathComponent(lectura.carpetaDeTemporada!)
        }

        switch (examen.forma, lectura) {
        case (.archivo(let video, let acompañantes), _):
            // Suelto: se le arma su carpeta (película) o va a la de la temporada (serie),
            // ya con el nombre limpio, y sus .srt/.nfo lo siguen con el mismo nombre.
            return piezas(video, acompañantes, nombre: nombreLimpio(de: video, lectura: lectura), hacia: destino)

        case (.carpeta(let videos), _):
            // Primero se le cambia el nombre al video DENTRO de la descarga y después se
            // mueve; así «Deshacer», que va al revés, deja todo como vino.
            let previos = renombresDentro(videos, lectura: lectura)
            let mapa = Dictionary(previos.map { ($0.desde, $0.hacia) }, uniquingKeysWith: { a, _ in a })
            return previos + mover(examen.origen, lectura: lectura, a: destino, renombrados: mapa)
        }
    }

    private static func mover(_ origen: URL, lectura: Lectura, a destino: URL,
                              renombrados: [URL: URL]) -> [Movimiento] {
        switch lectura {
        case .pelicula:
            // La carpeta entera pasa a llamarse «Título (Año)», con todo lo de dentro.
            return [Movimiento(desde: origen, hacia: destino)]

        case .serie(_, _, _?):
            // Un episodio en su propia carpeta: la carpeta entra en la de la temporada.
            let nombre = Analizador.colapsar(origen.lastPathComponent)
            return [Movimiento(desde: origen, hacia: destino.appendingPathComponent(nombre))]

        case .serie(_, _, nil):
            // Temporada entera: si la carpeta de la temporada aún no existe, la descarga
            // pasa a ser esa carpeta; si ya existe, se vacía dentro de ella.
            if !FileManager.default.fileExists(atPath: destino.path) {
                return [Movimiento(desde: origen, hacia: destino)]
            }
            let hijos = (try? FileManager.default.contentsOfDirectory(
                at: origen, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            return hijos.map { renombrados[$0] ?? $0 }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }.map {
                    Movimiento(desde: $0, hacia: destino.appendingPathComponent($0.lastPathComponent))
                }
        }
    }

    // MARK: - Nombre limpio

    /// Cómo se llama el video al quedar organizado: «Tony (2026)» o «Ted Lasso S03E11».
    /// nil = se queda como vino: un episodio doble (`S01E01E02`, se perdería el segundo)
    /// o un nombre del que no se saca el episodio.
    public static func nombreLimpio(de video: URL, lectura: Lectura) -> String? {
        switch lectura {
        case .pelicula:
            return lectura.carpeta
        case .serie(let nombre, _, _):
            let original = video.deletingPathExtension().lastPathComponent
            let doble = #"[Ss]\d{1,2}[Ee]\d{1,3}[-_. ]?[Ee]\d{1,3}"#
            if original.range(of: doble, options: .regularExpression) != nil { return nil }
            guard case .serie(_, let temporada, let episodio?)? = Analizador.leer(video.lastPathComponent) else {
                return nil
            }
            return "\(nombre) " + String(format: "S%02dE%02d", temporada, episodio)
        }
    }

    /// El video y lo que lleva su nombre (`peli.srt`, `peli.es.srt`, `peli.nfo`) hacia
    /// `carpeta`, con `nombre` en vez del de la descarga (`.es.srt` se conserva).
    static func piezas(_ video: URL, _ acompañantes: [URL], nombre: String?, hacia carpeta: URL) -> [Movimiento] {
        let viejo = video.deletingPathExtension().lastPathComponent
        return ([video] + acompañantes).map { pieza in
            var final = pieza.lastPathComponent
            if let nombre, final.hasPrefix(viejo) { final = nombre + final.dropFirst(viejo.count) }
            return Movimiento(desde: pieza, hacia: carpeta.appendingPathComponent(final))
        }
    }

    /// Los cambios de nombre dentro de una carpeta descargada, antes de moverla.
    /// En una película sólo si trae un único video (si trae extras, no se adivina cuál
    /// es). Dos capítulos que darían el mismo nombre (dos calidades) se quedan como vinieron.
    static func renombresDentro(_ videos: [URL], lectura: Lectura) -> [Movimiento] {
        if case .pelicula = lectura, videos.count != 1 { return [] }
        let nombres = videos.map { nombreLimpio(de: $0, lectura: lectura) }
        let repetidos = Set(Dictionary(grouping: nombres.compactMap { $0 }, by: { $0 }).filter { $0.value.count > 1 }.keys)
        return zip(videos, nombres).flatMap { video, nombre -> [Movimiento] in
            guard let nombre, !repetidos.contains(nombre),
                  nombre != video.deletingPathExtension().lastPathComponent else { return [] }
            return piezas(video, acompañantes(de: video), nombre: nombre, hacia: video.deletingLastPathComponent())
        }
    }

    /// Los videos que cambiaron de nombre en un lote ya hecho: dónde quedaron al final
    /// y cómo se llamaban al bajarlos (para guardarlo en el archivo).
    public static func videosRenombrados(_ hechos: [Movimiento]) -> [(video: URL, nombreOriginal: String)] {
        hechos.enumerated().compactMap { i, m in
            guard Analizador.esVideo(m.desde), m.desde.lastPathComponent != m.hacia.lastPathComponent else { return nil }
            var ruta = m.hacia.standardizedFileURL.path
            for despues in hechos[(i + 1)...] {
                let desde = despues.desde.standardizedFileURL.path
                if ruta.hasPrefix(desde + "/") {
                    ruta = despues.hacia.standardizedFileURL.path + ruta.dropFirst(desde.count)
                }
            }
            return (URL(fileURLWithPath: ruta), m.desde.lastPathComponent)
        }
    }

    // MARK: - Estado

    public enum Diagnostico: Equatable, Sendable {
        /// Ya está donde debe: no hay nada que hacer.
        case enOrden
        case listo
        /// Película sin año: puede confundirse con otra del mismo nombre.
        case sinAño
        /// Ya hay algo con ese nombre en el destino. Nunca se sobrescribe.
        case choque(String)
    }

    public static func diagnosticar(_ movimientos: [Movimiento], lectura: Lectura) -> Diagnostico {
        let pendientes = movimientos.filter { !mismaRuta($0.desde, $0.hacia) }
        if pendientes.isEmpty { return .enOrden }
        if let choque = pendientes.first(where: { FileManager.default.fileExists(atPath: $0.hacia.path) }) {
            return .choque(choque.hacia.lastPathComponent)
        }
        if case .pelicula(_, nil) = lectura { return .sinAño }
        return .listo
    }

    static func mismaRuta(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path.lowercased() == b.standardizedFileURL.path.lowercased()
    }

    // MARK: - Mover y deshacer

    public enum Falla: LocalizedError {
        case yaExiste(String)
        case noSePudo(String, String)

        public var errorDescription: String? {
            switch self {
            case .yaExiste(let nombre): return "Ya existe «\(nombre)» en el destino"
            case .noSePudo(let nombre, let motivo): return "No se pudo mover «\(nombre)»: \(motivo)"
            }
        }
    }

    /// Mueve pieza por pieza. ⛔ Nunca sobrescribe ni borra: si el destino existe, para.
    /// Devuelve lo que sí alcanzó a mover, para poder deshacerlo.
    public static func ejecutar(_ movimientos: [Movimiento]) -> (hechos: [Movimiento], falla: Falla?) {
        let fm = FileManager.default
        var hechos: [Movimiento] = []
        for m in movimientos where !mismaRuta(m.desde, m.hacia) {
            if fm.fileExists(atPath: m.hacia.path) { return (hechos, .yaExiste(m.hacia.lastPathComponent)) }
            do {
                try fm.createDirectory(at: m.hacia.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: m.desde, to: m.hacia)
                hechos.append(m)
            } catch {
                return (hechos, .noSePudo(m.desde.lastPathComponent, error.localizedDescription))
            }
        }
        return (hechos, nil)
    }

    /// Devuelve todo a donde estaba, en orden inverso. Las carpetas que se crearon por
    /// el camino se quedan (vacías): no se borra nada.
    public static func deshacer(_ movimientos: [Movimiento]) -> Falla? {
        let invertidos = movimientos.reversed().map { Movimiento(desde: $0.hacia, hacia: $0.desde) }
        return ejecutar(Array(invertidos)).falla
    }
}
