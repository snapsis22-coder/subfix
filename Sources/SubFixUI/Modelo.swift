import Foundation
import SubFixKit
import SwiftUI

/// Una película en la lista, con su diagnóstico y su estado.
///
/// Es un valor, no un objeto: cuando era una clase observable propia, la barra
/// inferior (que mira la Cola) no se enteraba de que una fila había cambiado de
/// estado y el botón Procesar se quedaba gris para siempre. Con la cola como
/// única fuente de verdad, cualquier cambio repinta toda la pantalla.
public struct Fila: Identifiable, Equatable {
    public let id = UUID()
    public internal(set) var url: URL

    public internal(set) var diagnostico: Motor.Diagnostico?
    var estado: Estado = .analizando
    var pistaElegida: Int?
    /// Si el usuario armó un MKV a medida, «Procesar» lo crea en vez de extraer el .srt.
    var plan: PlanDeMKV?
    /// Avance del MKV que se está creando (0…1) y cuándo empezó, para la barra y el tiempo restante.
    var progreso: Double?
    /// Lo que se creó al terminar (el MKV nuevo), para el botón «Mostrar».
    var archivoListo: URL?
    var inicioDeProgreso: Date?
    /// El de España que apareció cuando se buscaba latino: apartado, sin instalar,
    /// hasta que el usuario pulse «Usar el de España».
    public internal(set) var candidatoEspaña: URL?

    enum Estado: Equatable {
        case analizando
        case listaParaProcesar
        case procesando
        case hecha(String)
        case avisada(String)
        case fallada(String)

        var icono: String {
            switch self {
            case .analizando, .procesando: return "hourglass"
            case .listaParaProcesar: return "circle.dashed"
            case .hecha: return "checkmark.circle.fill"
            case .avisada: return "exclamationmark.triangle.fill"
            case .fallada: return "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .analizando, .procesando, .listaParaProcesar: return .secondary
            case .hecha: return .green
            case .avisada: return .orange
            case .fallada: return .red
            }
        }

        var detalle: String? {
            switch self {
            case .hecha(let t), .avisada(let t), .fallada(let t): return t
            case .procesando: return "procesando…"
            case .analizando: return "leyendo el archivo…"
            case .listaParaProcesar: return nil
            }
        }
    }

    init(url: URL) { self.url = url }

    public static func == (izquierda: Fila, derecha: Fila) -> Bool {
        izquierda.id == derecha.id && izquierda.estado == derecha.estado
            && izquierda.pistaElegida == derecha.pistaElegida && izquierda.plan == derecha.plan
            && izquierda.progreso == derecha.progreso && izquierda.candidatoEspaña == derecha.candidatoEspaña
    }

    var nombre: String { url.lastPathComponent }

    /// Quedó en naranja: sin subtítulo, o sólo con el de España.
    public var avisa: Bool { if case .avisada = estado { return true } else { return false } }
    public var terminada: Bool { if case .hecha = estado { return true } else { return false } }
    public var fallo: Bool { if case .fallada = estado { return true } else { return false } }
    /// Lo que el usuario tiene que mirar: avisos en naranja y fallos.
    public var porRevisar: Bool { avisa || fallo }
    public var esEpisodio: Bool { Motor.carpetaDeCapitulo(para: url) != nil }
    /// Ya vive en su carpeta «Serie SxxEyy».
    public var organizada: Bool {
        guard let carpeta = Motor.carpetaDeCapitulo(para: url) else { return true }
        return url.deletingLastPathComponent().lastPathComponent == carpeta
    }
    public var visible: NombreVisible { NombreVisible(url) }
}

/// Cómo se muestra un archivo en la lista: «S03E11 · Mom City» en vez de
/// «Ted.Lasso.S03E11.Mom.City.2160p.10bit.ATVP.WEB-DL.DDP5.1.HEVC-Vyndros.mkv».
public struct NombreVisible: Equatable {
    public let codigo: String?     // «S03E11» si es capítulo
    public let titulo: String      // «Mom City», «Unabomber (2026)»
    public let grupo: String       // «Ted Lasso · Temporada 3» o «Películas»
    public let orden: Int          // temporada*1000 + episodio, para ordenar dentro del grupo
    public let año: String?        // de las películas, si el nombre lo trae

    /// Fichas de calidad o de origen: ahí se acaba el título.
    static let fichaTecnica = try! NSRegularExpression(pattern:
        "^(\\d{3,4}p|4k|uhd|web|webrip|web-?dl|blu-?ray|brrip|bdrip|hdtv|dvdrip|[xh]\\.?26[45]|hevc|avc|"
        + "\\d+bit|hdr\\d*|dv|dovi|atvp|amzn|nf|dsnp|hmax|hulu|pcok|ddp?\\d.*|aac.*|ac3|eac3|dts.*|truehd|"
        + "atmos|remux|proper|repack|internal|multi|dual|subbed|\\[.*)$", options: [.caseInsensitive])

    static func esFichaTecnica(_ palabra: String) -> Bool {
        fichaTecnica.firstMatch(in: palabra, range: NSRange(palabra.startIndex..., in: palabra)) != nil
    }

    public init(_ url: URL) {
        let nombre = url.deletingPathExtension().lastPathComponent
        let partir: (Substring) -> [String] = { trozo in
            trozo.split(whereSeparator: { ". _".contains($0) }).map(String.init)
        }
        let (_, temporada, episodio) = OpenSubtitles.tituloLimpio(url)
        if let marca = nombre.range(of: "[Ss](\\d{1,2})[\\s._-]?[Ee](\\d{1,3})", options: .regularExpression),
           let temporada, let episodio {
            let serie = Motor.carpetaDeCapitulo(para: url)?
                .replacingOccurrences(of: "\\s*S\\d+E\\d+$", with: "", options: .regularExpression) ?? ""
            let palabras = partir(nombre[marca.upperBound...]).prefix { !Self.esFichaTecnica($0) }
            codigo = String(format: "S%02dE%02d", temporada, episodio)
            titulo = palabras.joined(separator: " ")
            grupo = (serie.isEmpty ? "Serie" : serie) + " · Temporada \(temporada)"
            orden = temporada * 1000 + episodio
            año = nil
        } else {
            let palabras = partir(nombre[...])
            var titulo: [String] = []
            var año: String?
            for palabra in palabras {
                if !titulo.isEmpty, palabra.range(of: "^\\(?(19|20)\\d\\d\\)?$", options: .regularExpression) != nil {
                    año = palabra.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                    break
                }
                if !titulo.isEmpty, Self.esFichaTecnica(palabra) { break }
                titulo.append(palabra)
            }
            codigo = nil
            let base = titulo.isEmpty ? nombre : titulo.joined(separator: " ")
            self.titulo = año.map { "\(base) (\($0))" } ?? base
            grupo = "Películas"
            orden = 0
            self.año = año
        }
    }
}

/// Las opciones de la barra se recuerdan entre sesiones. Las pruebas cambian el
/// almacén por uno desechable para no pisar las del usuario.
public enum Ajustes {
    nonisolated(unsafe) public static var almacen: UserDefaults = .standard

    static func leer(_ clave: String, _ porDefecto: Bool) -> Bool {
        almacen.object(forKey: "subfix." + clave) as? Bool ?? porDefecto
    }
    static func guardar(_ clave: String, _ valor: Bool) {
        almacen.set(valor, forKey: "subfix." + clave)
    }
}

@MainActor
public final class Cola: ObservableObject {
    @Published public var filas: [Fila] = []
    @Published public var trabajando = false
    @Published public var usarRed = Ajustes.leer("usarRed", true) {
        didSet { Ajustes.guardar("usarRed", usarRed) }
    }
    @Published public var preferirLatino = Ajustes.leer("preferirLatino", true) {
        didSet { Ajustes.guardar("preferirLatino", preferirLatino) }
    }
    @Published public var organizar = Ajustes.leer("organizar", false) {
        didSet { Ajustes.guardar("organizar", organizar) }
    }
    /// Apagado: «Procesar» sólo busca el subtítulo latino en la web. Encendido:
    /// además lo extrae de la pista del archivo (lo de antes).
    @Published public var extraerDelArchivo = Ajustes.leer("extraerDelArchivo", false) {
        didSet { Ajustes.guardar("extraerDelArchivo", extraerDelArchivo) }
    }
    /// Al terminar de procesar, abrir Subdivx con los que quedaron sin latino.
    @Published public var subdivxAlTerminar = Ajustes.leer("subdivxAlTerminar", true) {
        didSet { Ajustes.guardar("subdivxAlTerminar", subdivxAlTerminar) }
    }
    /// La vista lo mira: cuando trae filas, abre la ventana de Subdivx con ellas.
    @Published public var abrirSubdivxCon: [UUID]?
    /// Aviso pasajero de algo que salió bien (p. ej. «12 capítulos organizados»).
    @Published public var nota: String?
    @Published public var mensajeDeHerramientas: String?
    /// Aviso pasajero en la barra inferior (p. ej. un subtítulo sin dueño).
    @Published public var aviso: String?

    public init() {
        let faltan = Herramientas.faltantes
        if !faltan.isEmpty {
            mensajeDeHerramientas = "Falta \(faltan.joined(separator: " y ")). Instálalo con:  brew install ffmpeg"
        }
    }

    public func agregar(_ rutas: [URL]) {
        // Un .srt/.zip/.rar bajado a mano (Subdivx) no es una película: se le
        // busca dueño entre las de la lista. Una carpeta con videos es una serie.
        let subtitulos = Motor.subtitulos(en: rutas)
        if !subtitulos.isEmpty { adoptar(subtitulos) }

        let nuevas = Motor.videos(en: rutas)
            .filter { url in !filas.contains { $0.url == url } }
            .map(Fila.init)
        filas.append(contentsOf: nuevas)
        for fila in nuevas { analizar(fila.id, fila.url) }
    }

    private func analizar(_ id: UUID, _ url: URL) {
        Task.detached(priority: .userInitiated) {
            let diagnostico = Motor.diagnosticar(url)
            await MainActor.run {
                self.cambiar(id) { fila in
                    fila.diagnostico = diagnostico
                    fila.estado = .listaParaProcesar
                }
            }
        }
    }

    /// Todo cambio a una fila pasa por aquí, y así SwiftUI siempre se entera.
    private func cambiar(_ id: UUID, _ cambio: (inout Fila) -> Void) {
        guard let indice = filas.firstIndex(where: { $0.id == id }) else { return }
        cambio(&filas[indice])
    }

    public func elegirPista(_ id: UUID, indice: Int) {
        cambiar(id) { $0.pistaElegida = indice }
    }

    /// Lo bajado en la ventana de Subdivx: ya se sabe de qué fila es.
    /// `false` si no traía ningún .srt.
    public func adoptarDescarga(_ archivo: URL, para id: UUID) -> Bool {
        adoptarDescarga(archivo, entre: [id])
    }

    /// Lo bajado a mano en la ventana de Subdivx cuando no se sabe para cuál de sus filas era:
    /// se empareja por SxxEyy entre ellas.
    public func adoptarDescarga(_ archivo: URL, entre ids: [UUID]) -> Bool {
        let subtitulos = Motor.subtitulos(en: [archivo])
        let suyas = filas.filter { ids.contains($0.id) }
        guard !subtitulos.isEmpty, !suyas.isEmpty,
              !Motor.emparejar(subtitulos, con: suyas.map(\.url)).isEmpty else { return false }
        adoptar(subtitulos, solo: ids)
        return true
    }

    /// Las que quedaron en naranja: sin latino (o sólo con el de España).
    public var faltanEnSubdivx: [Fila] { filas.filter(\.avisa) }

    private func adoptar(_ subtitulos: [URL], solo ids: [UUID]? = nil) {
        var pares: [(video: URL, subtitulo: URL)]
        if let ids {
            pares = Motor.emparejar(subtitulos, con: filas.filter { ids.contains($0.id) }.map(\.url))
        } else {
            // Primero los que avisaron que les falta; si ninguno casa, cualquiera.
            let avisadas = filas.filter { if case .avisada = $0.estado { return true } else { return false } }
            pares = Motor.emparejar(subtitulos, con: avisadas.map(\.url))
            if pares.isEmpty { pares = Motor.emparejar(subtitulos, con: filas.map(\.url)) }
        }

        guard !pares.isEmpty else {
            let nombre = subtitulos.first?.lastPathComponent ?? "el subtítulo"
            aviso = filas.isEmpty
                ? "Arrastra primero la película o el capítulo, y luego su subtítulo."
                : "No supe a qué capítulo o película corresponde «\(nombre)»."
            return
        }
        aviso = nil
        let organizarlos = organizar
        let latino = preferirLatino

        for par in pares {
            guard let fila = filas.first(where: { $0.url == par.video }) else { continue }
            let id = fila.id
            let esEpisodio = fila.diagnostico?.esEpisodio ?? (Motor.carpetaDeCapitulo(para: fila.url) != nil)
            cambiar(id) { $0.estado = .procesando }
            Task.detached(priority: .userInitiated) {
                let resultado = Motor.adoptar(par.subtitulo, para: par.video, retenerEspaña: latino)
                let final = await self.ordenar(id, par.video, resultado, esEpisodio: esEpisodio,
                                               organizar: organizarlos, preferirLatino: latino)
                await MainActor.run {
                    self.cambiar(id) { $0.estado = final }
                    Motor.limpiarFantasmas(en: [self.filas.first { $0.id == id }?.url.deletingLastPathComponent()
                                                ?? par.video.deletingLastPathComponent()])
                }
            }
        }
    }

    /// Traduce el resultado y, si corresponde, mete el capítulo en su carpeta.
    private func ordenar(_ id: UUID, _ video: URL, _ resultado: Motor.Resultado, esEpisodio: Bool,
                         organizar: Bool, preferirLatino: Bool) -> Fila.Estado {
        var estado = Self.traducir(resultado, preferirLatino: preferirLatino)
        if case .soloEspaña(_, let candidato) = resultado {
            cambiar(id) { $0.candidatoEspaña = candidato }
        } else if resultado.fueBien {
            cambiar(id) { $0.candidatoEspaña = nil }   // ya quedó otro (p. ej. el latino de Subdivx)
        }
        // Sólo se mueve lo que quedó con subtítulo: lo que falló se queda
        // a la vista, donde estaba.
        guard organizar, resultado.fueBien, esEpisodio else { return estado }
        do {
            let nueva = try Motor.organizarPorCapitulo(video)
            cambiar(id) { $0.url = nueva }
            let carpeta = " · en «\(nueva.deletingLastPathComponent().lastPathComponent)»"
            switch estado {
            case .hecha(let texto): estado = .hecha(texto + carpeta)
            case .avisada(let texto): estado = .avisada(texto + carpeta)
            default: break
            }
        } catch {
            estado = .avisada("subtítulo listo, pero \(error.localizedDescription)")
        }
        return estado
    }

    /// Se creó un MKV desde la hoja: si la fila seguía pendiente, ya no hay nada
    /// que procesar (no hace falta dejar un .srt suelto).
    public func mkvCreado(_ id: UUID, _ mkv: URL) {
        cambiar(id) { fila in
            fila.plan = nil
            fila.archivoListo = mkv
            if fila.estado == .listaParaProcesar { fila.estado = .hecha("MKV creado: \(mkv.lastPathComponent)") }
        }
    }

    /// Deja armado el MKV de una fila: «Procesar» lo creará. Con `nil` se descarta
    /// y la fila vuelve a extraer el .srt como siempre.
    public func guardarPlan(_ id: UUID, _ plan: PlanDeMKV?) {
        cambiar(id) { $0.plan = plan }
    }

    /// El usuario aceptó el de España que había quedado apartado: ahora sí se instala.
    public func usarEspaña(_ id: UUID) {
        guard let fila = filas.first(where: { $0.id == id }), let candidato = fila.candidatoEspaña else { return }
        let video = fila.url
        let organizarlos = organizar
        let esEpisodio = fila.diagnostico?.esEpisodio ?? (Motor.carpetaDeCapitulo(para: video) != nil)
        cambiar(id) { $0.estado = .procesando; $0.candidatoEspaña = nil }
        Task.detached(priority: .userInitiated) {
            let resultado = Motor.adoptar(candidato, para: video)
            // Ya lo aceptó sabiendo que es de España: no se le vuelve a avisar.
            let final = await self.ordenar(id, video, resultado, esEpisodio: esEpisodio,
                                           organizar: organizarlos, preferirLatino: false)
            await MainActor.run {
                self.cambiar(id) { $0.estado = final }
                Motor.limpiarFantasmas(en: [video.deletingLastPathComponent()])
            }
        }
    }

    /// Quita la fila de la lista. No toca ningún archivo.
    public func quitar(_ id: UUID) {
        guard filas.first(where: { $0.id == id })?.estado != .procesando else { return }
        filas.removeAll { $0.id == id }
    }

    /// Una fila que falló vuelve a quedar pendiente (conserva su plan de MKV, si lo tenía).
    public func reintentar(_ id: UUID) {
        cambiar(id) { fila in
            guard fila.fallo || fila.avisa else { return }
            fila.estado = .listaParaProcesar
            fila.progreso = nil
        }
    }

    public var hayCapitulosPorOrganizar: Bool {
        filas.contains { $0.esEpisodio && !$0.organizada && $0.estado != .procesando }
    }

    /// Mete AHORA cada capítulo de la lista en su carpeta «Serie SxxEyy», tenga o no
    /// subtítulo. Mover en el mismo disco es renombrar; nunca pisa nada.
    public func organizarTodos() {
        guard !trabajando else { return }
        var movidos = 0
        var problemas: [String] = []
        for fila in filas where fila.esEpisodio && !fila.organizada && fila.estado != .procesando {
            do {
                let nueva = try Motor.organizarPorCapitulo(fila.url)
                let carpetaVieja = fila.url.deletingLastPathComponent()
                cambiar(fila.id) { f in
                    f.url = nueva
                    if let listo = f.archivoListo, listo.deletingLastPathComponent() == carpetaVieja {
                        f.archivoListo = nueva.deletingLastPathComponent().appendingPathComponent(listo.lastPathComponent)
                    }
                }
                movidos += 1
            } catch {
                problemas.append("\(fila.visible.codigo ?? fila.nombre): \(error.localizedDescription)")
            }
        }
        if problemas.isEmpty {
            aviso = nil
            nota = movidos == 1 ? "1 capítulo quedó en su carpeta." : "\(movidos) capítulos quedaron cada uno en su carpeta."
        } else {
            nota = nil
            aviso = "No pude organizar \(problemas.count): " + problemas.joined(separator: " · ")
        }
    }

    public func vaciar() {
        filas.removeAll()
    }

    public var pendientes: [Fila] {
        // Una fila que falló al crear su MKV conserva el plan: se puede reintentar sin volver a armarlo.
        filas.filter { fila in
            if fila.estado == .listaParaProcesar { return true }
            if case .fallada = fila.estado, fila.plan != nil { return true }
            return false
        }
    }

    public func procesarTodo() {
        guard !trabajando else { return }
        trabajando = true
        let porHacer = pendientes
        let red = usarRed
        let latino = preferirLatino
        let organizarlos = organizar
        let extraer = extraerDelArchivo

        Task {
            for fila in porHacer {
                cambiar(fila.id) { $0.estado = .procesando }
                if let plan = fila.plan {
                    let video = fila.url, id = fila.id
                    cambiar(id) { $0.progreso = 0; $0.inicioDeProgreso = Date() }
                    do {
                        let mkv = try await Task.detached(priority: .userInitiated) {
                            try Remux.hacer(video: video, plan: plan) { avance in
                                Task { @MainActor [weak self] in self?.cambiar(id) { $0.progreso = avance } }
                            }
                        }.value
                        cambiar(id) { $0.plan = nil; $0.progreso = nil; $0.archivoListo = mkv
                                      $0.estado = .hecha("MKV creado: \(mkv.lastPathComponent)") }
                    } catch {
                        cambiar(id) { $0.progreso = nil; $0.estado = .fallada(error.localizedDescription) }
                    }
                    continue
                }
                let opciones = Motor.Opciones(usarRed: red, forzar: false,
                                              pistaPreferida: fila.pistaElegida,
                                              preferirLatino: latino, extraerDelArchivo: extraer,
                                              retenerEspaña: latino)
                let resultado = await Motor.procesar(fila.url, opciones: opciones)
                let estado = ordenar(fila.id, fila.url, resultado,
                                     esEpisodio: fila.diagnostico?.esEpisodio == true,
                                     organizar: organizarlos, preferirLatino: latino)
                cambiar(fila.id) { $0.estado = estado }
            }
            let carpetas = Set(porHacer.compactMap { hecha in
                filas.first { $0.id == hecha.id }?.url.deletingLastPathComponent()
            } + porHacer.map { $0.url.deletingLastPathComponent() })
            Motor.limpiarFantasmas(en: carpetas)
            trabajando = false
            if subdivxAlTerminar {
                let faltan = porHacer.map(\.id).filter { id in filas.first { $0.id == id }?.avisa == true }
                if !faltan.isEmpty { abrirSubdivxCon = faltan }
            }
        }
    }

    /// Las que «Latino por defecto» puede tocar: todas las ya leídas que no estén trabajando.
    public var paraLatinoPorDefecto: [Fila] {
        filas.filter { $0.estado != .analizando && $0.estado != .procesando }
    }

    /// Botón «Latino por defecto»: sólo eso. A cada MKV de la lista le deja automático
    /// el subtítulo latino y, si lo trae, el audio latino. Modifica el MISMO archivo
    /// (sólo la cabecera, no el video): no busca en internet, no extrae, no crea otro.
    public func latinoPorDefectoEnTodos() {
        guard !trabajando else { return }
        trabajando = true
        let porHacer = paraLatinoPorDefecto

        Task {
            var cambiados = 0, yaEstaban = 0, sinLatino = 0, fallos = 0
            for fila in porHacer {
                let video = fila.url, id = fila.id
                let antes = fila.estado
                cambiar(id) { $0.estado = .procesando }
                do {
                    let resultado = try await Task.detached(priority: .userInitiated) {
                        try CabeceraMKV.latinoPorDefecto(video)
                    }.value
                    switch resultado {
                    case .cambiado(let texto):
                        cambiados += 1
                        cambiar(id) { $0.estado = .hecha(texto); $0.archivoListo = video }
                    case .yaEstaba(let texto):
                        yaEstaban += 1
                        cambiar(id) { $0.estado = .hecha(texto) }
                    case .sinLatino:
                        sinLatino += 1
                        cambiar(id) { $0.estado = antes == .listaParaProcesar ? .avisada("no trae subtítulo ni audio latino") : antes }
                    }
                } catch {
                    fallos += 1
                    cambiar(id) { $0.estado = .fallada(error.localizedDescription) }
                }
            }
            trabajando = false
            var partes: [String] = []
            if cambiados > 0 { partes.append("\(cambiados) con latino por defecto") }
            if yaEstaban > 0 { partes.append("\(yaEstaban) ya estaban así") }
            if sinLatino > 0 { partes.append("\(sinLatino) sin latino dentro") }
            if fallos > 0 { partes.append("\(fallos) no se pudieron") }
            nota = partes.joined(separator: " · ") + "."
        }
    }

    /// Botón «Extraer latino»: sólo eso, en toda la lista. Saca del archivo el subtítulo
    /// latino, lo limpia (publicidad, etiquetas, caracteres) y lo deja como .srt al lado,
    /// que es el que el TV pone solo. Al final mete cada capítulo en su carpeta
    /// «Serie SxxEyy» (si ya está en una, no la toca). No busca en internet.
    public func extraerLatinoEnTodos() {
        guard !trabajando else { return }
        trabajando = true
        let porHacer = paraLatinoPorDefecto

        Task {
            var listos = 0, sinLatino = 0, fallos = 0
            for fila in porHacer {
                let video = fila.url, id = fila.id
                cambiar(id) { $0.estado = .procesando }
                let resultado = await Motor.procesar(video, opciones: Motor.extraerLatino)
                var estado = Self.traducir(resultado)
                // Si dentro no hay latino pero al lado ya hay un .srt latino (p. ej. de Subdivx), ése vale.
                let yaTeniaLatino = (try? TextoSRT.leer(Motor.destinoSRT(de: video)).texto).map {
                    TextoSRT.esSRT($0) && TextoSRT.pareceEspañol($0) && !TextoSRT.pareceDeEspaña($0)
                } ?? false
                switch resultado {
                case .soloEspaña where yaTeniaLatino, .sinSubtitulos where yaTeniaLatino:
                    estado = .hecha("dentro no hay latino: se quedó el .srt latino que ya tenía")
                case .soloEspaña(_, let candidato):
                    estado = .avisada("el subtítulo del archivo es de España — no lo puse hasta que lo apruebes")
                    cambiar(id) { $0.candidatoEspaña = candidato }
                case .sinSubtitulos:
                    estado = .avisada("no trae subtítulo en español dentro")
                default:
                    break
                }
                switch estado {
                case .hecha: listos += 1; cambiar(id) { $0.archivoListo = Motor.destinoSRT(de: video) }
                case .fallada: fallos += 1
                default: sinLatino += 1
                }
                cambiar(id) { $0.estado = estado }
            }
            Motor.limpiarFantasmas(en: Set(porHacer.map { $0.url.deletingLastPathComponent() }))
            trabajando = false
            var partes: [String] = []
            if listos > 0 { partes.append("\(listos) con su .srt latino limpio") }
            if sinLatino > 0 { partes.append("\(sinLatino) sin latino dentro") }
            if fallos > 0 { partes.append("\(fallos) fallaron") }
            let resumen = partes.joined(separator: " · ") + "."
            nota = resumen
            if hayCapitulosPorOrganizar {
                organizarTodos()
                if let movidos = nota, movidos != resumen { nota = resumen + " " + movidos }
            }
        }
    }

    // Los textos de aviso son cortos: el botón naranja «Subdivx» ya dice qué hacer.

    static func traducir(_ resultado: Motor.Resultado, preferirLatino: Bool = true) -> Fila.Estado {
        switch resultado {
        case .listo(let origen, let lineas, let publicidad, let etiquetas, let depurados, let deEspaña):
            if preferirLatino, deEspaña {
                return .avisada("no hubo latino: quedó el de España (\(origen))")
            }
            var texto = "\(lineas) líneas · \(origen)"
            if publicidad > 0 { texto += " · \(publicidad) bloque(s) de publicidad fuera" }
            if etiquetas > 0 { texto += " · \(etiquetas) línea(s) con etiquetas de formato limpiadas" }
            if depurados > 0 { texto += " · \(depurados) línea(s) con caracteres basura depuradas" }
            return .hecha(texto)
        case .reparado(_, true) where preferirLatino, .yaEstaba(true) where preferirLatino:
            return .avisada("el .srt que tiene es de España")
        case .reparado(let codificacion, _):
            return .hecha("el .srt que ya estaba venía en \(codificacion) — corregido")
        case .yaEstaba:
            return .hecha("ya tenía subtítulo correcto")
        case .sinSubtitulos(let soloImagen):
            return .avisada(soloImagen
                ? "sólo trae subtítulos de imagen y no encontré uno de texto"
                : "no encontré subtítulo en español")
        case .soloEspaña(let origen, _):
            return .avisada("sólo hay de España (\(origen)) — no lo puse hasta que lo apruebes")
        case .falló(let motivo):
            return .fallada(motivo)
        }
    }
}
