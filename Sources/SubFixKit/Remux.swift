import Foundation

/// Reempaqueta una película en un .mkv nuevo sin recodificar nada: se queda con
/// el video, los audios elegidos, los capítulos y los adjuntos, descarta todos
/// los subtítulos del original y mete el .srt que SubFix dejó listo.
///
/// Es lo que antes se hacía a mano en MKVToolNix, con la ventaja de que el .srt
/// ya va en UTF-8 y no hay que adivinar su codificación. El original no se toca.
/// De dónde sale el subtítulo que se mete en el MKV.
public enum FuenteDeSubtitulo: Hashable, Sendable {
    /// Una pista de texto que el MKV ya trae (se extrae a un temporal, no junto al video).
    case pista(Pista)
    /// El .srt que ya está junto a la película.
    case existente(URL)
    /// Un .srt, .zip o .rar que el usuario eligió (p. ej. el de Subdivx).
    case archivo(URL)
}

/// Un idioma de la lista preestablecida: el código que lee el reproductor (ISO 639-2)
/// y el nombre con el que se rotula la pista.
public struct Idioma: Hashable, Sendable, Identifiable {
    public let codigo: String
    public let nombre: String
    public var id: String { codigo + nombre }

    public init(codigo: String, nombre: String) {
        self.codigo = codigo
        self.nombre = nombre
    }

    public static let sinIdioma = Idioma(codigo: "und", nombre: "Sin idioma")
    public static let español = Idioma(codigo: "spa", nombre: "Español")

    /// Códigos como los escribe MKVToolNix (ISO 639-2 bibliográfico: fre, ger, chi…).
    public static let lista: [Idioma] = [
        español,
        Idioma(codigo: "spa", nombre: "Español (Latinoamérica)"),
        Idioma(codigo: "spa", nombre: "Español (España)"),
        Idioma(codigo: "eng", nombre: "English"),
        Idioma(codigo: "por", nombre: "Português (Brasil)"),
        Idioma(codigo: "por", nombre: "Português (Portugal)"),
        Idioma(codigo: "fre", nombre: "Français"),
        Idioma(codigo: "ita", nombre: "Italiano"),
        Idioma(codigo: "ger", nombre: "Deutsch"),
        Idioma(codigo: "dut", nombre: "Nederlands"),
        Idioma(codigo: "cat", nombre: "Català"),
        Idioma(codigo: "swe", nombre: "Svenska"),
        Idioma(codigo: "pol", nombre: "Polski"),
        Idioma(codigo: "rus", nombre: "Русский"),
        Idioma(codigo: "tur", nombre: "Türkçe"),
        Idioma(codigo: "ara", nombre: "العربية"),
        Idioma(codigo: "heb", nombre: "עברית"),
        Idioma(codigo: "hin", nombre: "हिन्दी"),
        Idioma(codigo: "jpn", nombre: "日本語"),
        Idioma(codigo: "kor", nombre: "한국어"),
        Idioma(codigo: "chi", nombre: "中文"),
        sinIdioma,
    ]

    /// Una pista sin idioma declarado (o «und»): la que conviene rotular.
    public static func estaSinEspecificar(_ codigo: String?) -> Bool {
        guard let codigo = codigo?.lowercased() else { return true }
        return codigo.isEmpty || codigo == "und" || codigo == "unk"
    }
}

/// Lo que el usuario dejó armado para el MKV de una película: qué audios, qué
/// subtítulos del propio archivo, qué .srt añadidos, cómo se llama el archivo y en
/// qué idioma se rotula cada pista. Se guarda en la fila y lo ejecuta «Procesar».
public struct PlanDeMKV: Equatable, Sendable {
    public var audios: [Int]
    public var subtitulosDelArchivo: [Pista]
    public var añadidos: [URL]
    /// Nombre del archivo sin «.mkv»; nil = el de siempre («Película (SubFix)»).
    public var nombre: String?
    /// Idioma que se pone a una pista (por su índice en el archivo); sin entrada = se deja como está.
    public var idiomasDeAudio: [Int: Idioma]
    public var idiomasDeSubtitulo: [Int: Idioma]
    /// Idioma de cada .srt añadido; sin entrada = Español.
    public var idiomasDeAñadidos: [URL: Idioma]

    public init(audios: [Int], subtitulosDelArchivo: [Pista], añadidos: [URL],
                nombre: String? = nil, idiomasDeAudio: [Int: Idioma] = [:],
                idiomasDeSubtitulo: [Int: Idioma] = [:], idiomasDeAñadidos: [URL: Idioma] = [:]) {
        self.audios = audios
        self.subtitulosDelArchivo = subtitulosDelArchivo
        self.añadidos = añadidos
        self.nombre = nombre
        self.idiomasDeAudio = idiomasDeAudio
        self.idiomasDeSubtitulo = idiomasDeSubtitulo
        self.idiomasDeAñadidos = idiomasDeAñadidos
    }

    public var resumen: String {
        let a = audios.count, s = subtitulosDelArchivo.count + añadidos.count
        var texto = "MKV nuevo: \(a) audio\(a == 1 ? "" : "s") · \(s) subtítulo\(s == 1 ? "" : "s")"
        if !añadidos.isEmpty { texto += " (\(añadidos.count) añadido\(añadidos.count == 1 ? "" : "s"))" }
        if let nombre, !nombre.isEmpty { texto += " · «\(nombre).mkv»" }
        return texto
    }
}

public enum Remux {

    /// Lo que se deja escribir como nombre: sin «.mkv», sin separadores de ruta, sin
    /// punto inicial (quedaría oculto). Vacío = nil, o sea el nombre de siempre.
    public static func nombreLimpio(_ texto: String?) -> String? {
        guard var nombre = texto?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if nombre.lowercased().hasSuffix(".mkv") { nombre.removeLast(4) }
        nombre = nombre.replacingOccurrences(of: "[/:]", with: "-", options: .regularExpression)
        nombre = nombre.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return nombre.isEmpty ? nil : nombre
    }

    /// «Película.mkv» → «Película (SubFix).mkv», en la misma carpeta; o el nombre que
    /// el usuario escribió. Si ya existe, se numera («(SubFix 2)», «(2)»…): nunca pisa ni borra nada.
    public static func destino(para video: URL, nombre: String? = nil) -> URL {
        let carpeta = video.deletingLastPathComponent()
        let propio = nombreLimpio(nombre)
        let base = propio ?? "\(video.deletingPathExtension().lastPathComponent) (SubFix)"
        var candidato = carpeta.appendingPathComponent("\(base).mkv")
        var n = 2
        while FileManager.default.fileExists(atPath: candidato.path) {
            let numerado = propio != nil
                ? "\(base) (\(n))"
                : "\(video.deletingPathExtension().lastPathComponent) (SubFix \(n))"
            candidato = carpeta.appendingPathComponent("\(numerado).mkv")
            n += 1
        }
        return candidato
    }

    /// Los argumentos de ffmpeg; aparte para poder probarlos sin ejecutar nada.
    /// `preparados`: los .srt añadidos ya limpios, en el mismo orden que `plan.añadidos`.
    public static func argumentos(video: URL, plan: PlanDeMKV, preparados: [URL], salida: URL) -> [String] {
        let audios = plan.audios, conservar = plan.subtitulosDelArchivo
        var args = ["-nostdin", "-v", "error", "-y", "-i", video.path]
        for srt in preparados { args += ["-i", srt.path] }
        args += ["-map", "0:v"]
        for indice in audios { args += ["-map", "0:\(indice)"] }
        for pista in conservar { args += ["-map", "0:\(pista.indice)"] }
        for k in preparados.indices { args += ["-map", "\(k + 1):0"] }
        args += ["-map_chapters", "0", "-map", "0:t?", "-c", "copy"]

        // mov_text (MP4) no cabe tal cual en un MKV: se convierte a SRT real.
        for (i, pista) in conservar.enumerated() where pista.codec == "mov_text" {
            args += ["-c:s:\(i)", "srt"]
        }

        // Idioma de cada pista: código + nombre. «und» no lleva título.
        func rotular(_ tipo: String, _ posicion: Int, _ idioma: Idioma) -> [String] {
            ["-metadata:s:\(tipo):\(posicion)", "language=\(idioma.codigo)",
             "-metadata:s:\(tipo):\(posicion)", "title=\(idioma == .sinIdioma ? "" : idioma.nombre)"]
        }
        for (i, indice) in audios.enumerated() {
            if let idioma = plan.idiomasDeAudio[indice] { args += rotular("a", i, idioma) }
        }
        for (i, pista) in conservar.enumerated() {
            if let idioma = plan.idiomasDeSubtitulo[pista.indice] { args += rotular("s", i, idioma) }
        }
        for (k, url) in plan.añadidos.enumerated() where k < preparados.count {
            args += rotular("s", conservar.count + k, plan.idiomasDeAñadidos[url] ?? .español)
        }

        // Sólo uno por defecto: el añadido, o si no hay, el primero en español del archivo.
        let total = conservar.count + preparados.count
        let porDefecto = !preparados.isEmpty ? conservar.count : conservar.firstIndex(where: \.esEspañol)
        for i in 0..<total {
            args += ["-disposition:s:\(i)", i == porDefecto ? "+default" : "-default"]
        }
        // El primer audio se reproduce por defecto; el resto, no.
        for (posicion, _) in audios.enumerated() {
            args += ["-disposition:a:\(posicion)", posicion == 0 ? "+default" : "-default"]
        }
        return args + ["-f", "matroska", salida.path]
    }

    /// Compatibilidad: un solo .srt ya preparado y ningún subtítulo del archivo.
    public static func argumentos(video: URL, subtitulo: URL, audios: [Int], salida: URL) -> [String] {
        argumentos(video: video, plan: PlanDeMKV(audios: audios, subtitulosDelArchivo: [], añadidos: [subtitulo]),
                   preparados: [subtitulo], salida: salida)
    }

    /// Crea el .mkv junto al original y devuelve su ruta. Nunca pisa un archivo.
    @discardableResult
    public static func hacer(video: URL, subtitulo: URL, audios: [Int]) throws -> URL {
        try ejecutar(video: video, plan: PlanDeMKV(audios: audios, subtitulosDelArchivo: [], añadidos: [subtitulo]),
                     preparados: [subtitulo])
    }

    /// Lo mismo, desde un plan: los .srt añadidos se limpian aquí y los temporales se borran al final.
    @discardableResult
    public static func hacer(video: URL, plan: PlanDeMKV,
                             progreso: (@Sendable (Double) -> Void)? = nil) throws -> URL {
        var temporales: [URL] = []
        defer { for url in temporales { try? FileManager.default.removeItem(at: url) } }
        for url in plan.añadidos {
            temporales.append(try prepararSubtitulo(.archivo(url), para: video))
        }
        return try ejecutar(video: video, plan: plan, preparados: temporales, progreso: progreso)
    }

    private static func ejecutar(video: URL, plan: PlanDeMKV, preparados: [URL],
                                 progreso: (@Sendable (Double) -> Void)? = nil) throws -> URL {
        let final = destino(para: video, nombre: plan.nombre)
        guard !FileManager.default.fileExists(atPath: final.path) else {
            throw ErrorDeSubFix.fallóElRemux("ya existe «\(final.lastPathComponent)» junto a la película")
        }
        guard !plan.audios.isEmpty else { throw ErrorDeSubFix.fallóElRemux("no quedó ningún audio marcado") }

        // Se escribe con otro nombre y sólo al terminar bien se pone el definitivo:
        // un corte a medias no deja un .mkv truncado que parezca bueno.
        let parcial = final.deletingLastPathComponent()
            .appendingPathComponent(".\(final.deletingPathExtension().lastPathComponent).parcial")
        var args = argumentos(video: video, plan: plan, preparados: preparados, salida: parcial)
        let salida: Herramientas.Salida
        if let progreso, let total = Sondeo.duracion(de: video), total > 0 {
            // ffmpeg cuenta cuánto video lleva escrito («out_time_us»); contra la duración da el avance.
            args.insert(contentsOf: ["-progress", "pipe:1", "-nostats"], at: 0)
            progreso(0)
            salida = try Herramientas.correr("ffmpeg", args) { linea in
                guard linea.hasPrefix("out_time_us="), let micro = Double(linea.dropFirst(12)), micro >= 0 else { return }
                progreso(min(1, micro / 1_000_000 / total))
            }
        } else {
            salida = try Herramientas.correr("ffmpeg", args)
        }
        let tamaño = ((try? FileManager.default.attributesOfItem(atPath: parcial.path))?[.size] as? Int) ?? 0
        guard salida.codigo == 0, tamaño > 0 else {
            try? FileManager.default.removeItem(at: parcial)   // sólo el parcial que acabo de crear
            throw ErrorDeSubFix.fallóElRemux(salida.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try FileManager.default.moveItem(at: parcial, to: final)
        progreso?(1)
        return final
    }

    /// Deja el subtítulo limpio (sin etiquetas, sin basura, sin publicidad) en un
    /// .srt temporal con el formato del TV y devuelve su ruta. No escribe nada junto
    /// a la película: el .srt sólo existe mientras se arma el MKV.
    public static func prepararSubtitulo(_ fuente: FuenteDeSubtitulo, para video: URL) throws -> URL {
        let texto: String
        switch fuente {
        case .pista(let pista):
            let crudo = FileManager.default.temporaryDirectory
                .appendingPathComponent("subfix-\(UUID().uuidString).srt")
            defer { try? FileManager.default.removeItem(at: crudo) }
            try Sondeo.extraer(pista: pista, de: video, a: crudo)
            texto = try TextoSRT.leer(crudo).texto
        case .existente(let url):
            texto = try TextoSRT.leer(url).texto
        case .archivo(let url):
            let candidatos = Motor.subtitulos(en: [url])
            guard let elegido = Motor.emparejar(candidatos, con: [video]).first?.subtitulo else {
                throw ErrorDeSubFix.fallóElRemux("no encontré ningún .srt dentro de «\(url.lastPathComponent)»")
            }
            texto = try TextoSRT.leer(elegido).texto
        }
        let limpio = TextoSRT.quitarPublicidad(
            TextoSRT.depurarCaracteres(TextoSRT.quitarEtiquetasASS(texto).texto).texto).texto
        guard TextoSRT.esSRT(limpio) else {
            throw ErrorDeSubFix.fallóElRemux("ese subtítulo no parece un .srt válido")
        }
        let temporal = FileManager.default.temporaryDirectory
            .appendingPathComponent("subfix-mkv-\(UUID().uuidString).srt")
        try TextoSRT.escribirParaElTV(limpio, en: temporal)
        return temporal
    }
}
