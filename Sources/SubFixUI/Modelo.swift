import AppKit
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
    /// El MKV que SubFix hizo a partir de este video: si existe, este es «el viejo» y se ofrece la Papelera.
    var versionNueva: URL?
    var inicioDeProgreso: Date?
    /// El de España que apareció cuando se buscaba latino: apartado, sin instalar,
    /// hasta que el usuario pulse «Usar el de España».
    public internal(set) var candidatoEspaña: URL?
    /// Huellas de los subtítulos que el usuario rechazó con «Reprocesar»: no se vuelven a poner.
    var descartados: Set<String> = []
    /// «Reprocesar»: buscar aunque ya tenga .srt (el que tiene se aparta sólo si aparece otro).
    var forzar = false

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
            case .analizando, .procesando, .listaParaProcesar: return Tema.tintaSuave
            case .hecha: return Tema.verde
            case .avisada: return Tema.ambar
            case .fallada: return Tema.rojo
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
    /// El texto de la fila tal como se ve («1.234 líneas · …», «sólo hay de España…»).
    public var detalle: String? { estado.detalle }
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
        refrescarVersiones()
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

    /// Qué pasó al probar lo bajado de Subdivx: la ventana sigue con el siguiente si no sirvió.
    public enum Prueba: Equatable {
        case latino        // quedó puesto: latino (o el que se pidió) y sincronizado o corregido
        case soloEspaña    // sólo traía el de España: apartado para «Usar el de España»
        case desfasado     // traía subtítulo, pero no va con este video
        case nada          // no traía un .srt para esta fila
    }

    /// Lo bajado en la ventana de Subdivx para una fila: se prueba y, si sirve, se instala.
    public func probarDescarga(_ archivo: URL, para id: UUID) async -> Prueba {
        await probarDescarga(archivo, entre: [id])
    }

    /// Lo bajado cuando no se sabe para cuál de sus filas era: se reparte por SxxEyy.
    public func probarDescarga(_ archivo: URL, entre ids: [UUID]) async -> Prueba {
        let subtitulos = await Task.detached { Motor.subtitulos(en: [archivo]) }.value
        let suyas = filas.filter { ids.contains($0.id) }
        var mejor = Prueba.nada
        for par in Motor.repartir(subtitulos, con: suyas.map(\.url)) {
            guard let fila = filas.first(where: { $0.url == par.video }) else { continue }
            let prueba = await adoptarComprobando(fila.id, par.subtitulos)
            if [Prueba.latino, .soloEspaña, .desfasado, .nada].firstIndex(of: prueba)!
                < [Prueba.latino, .soloEspaña, .desfasado, .nada].firstIndex(of: mejor)! { mejor = prueba }
        }
        return mejor
    }

    /// Las que quedaron en naranja: sin latino (o sólo con el de España).
    public var faltanEnSubdivx: [Fila] { filas.filter(\.avisa) }

    /// Un .srt/.zip soltado en la ventana o elegido con «Añadir…»: se le busca dueño.
    private func adoptar(_ subtitulos: [URL]) {
        // Primero los que avisaron que les falta; si ninguno casa, cualquiera.
        let avisadas = filas.filter(\.avisa)
        var pares = Motor.repartir(subtitulos, con: avisadas.map(\.url))
        if pares.isEmpty { pares = Motor.repartir(subtitulos, con: filas.map(\.url)) }

        guard !pares.isEmpty else {
            let nombre = subtitulos.first?.lastPathComponent ?? "el subtítulo"
            aviso = filas.isEmpty
                ? "Arrastra primero la película o el capítulo, y luego su subtítulo."
                : "No supe a qué capítulo o película corresponde «\(nombre)»."
            return
        }
        aviso = nil
        for par in pares {
            guard let fila = filas.first(where: { $0.url == par.video }) else { continue }
            Task { await adoptarComprobando(fila.id, par.subtitulos) }
        }
    }

    /// De varios .srt para una fila, instala el que va sincronizado (y latino, si se pidió).
    /// Si ninguno sirve, la fila se queda como estaba: lo que ya tenía no se toca.
    @discardableResult
    private func adoptarComprobando(_ id: UUID, _ subtitulos: [URL]) async -> Prueba {
        guard let fila = filas.first(where: { $0.id == id }), fila.estado != .procesando else { return .nada }
        let video = fila.url, antes = fila.estado, descartados = fila.descartados
        let latino = preferirLatino, organizarlos = organizar
        let esEpisodio = fila.diagnostico?.esEpisodio ?? (Motor.carpetaDeCapitulo(para: video) != nil)
        cambiar(id) { $0.estado = .procesando }
        let resultado = await Task.detached(priority: .userInitiated) {
            Motor.adoptarComprobando(subtitulos, para: video, preferirLatino: latino, descartados: descartados)
        }.value
        defer { Motor.limpiarFantasmas(en: [filas.first { $0.id == id }?.url.deletingLastPathComponent()
                                           ?? video.deletingLastPathComponent()]) }
        switch resultado {
        case .listo, .reparado, .yaEstaba:
            let final = ordenar(id, video, resultado, esEpisodio: esEpisodio, organizar: organizarlos, preferirLatino: latino)
            cambiar(id) { $0.estado = final; $0.forzar = false }
            return .latino
        case .soloEspaña:
            // Si ya había uno de España apartado, no se pisa con otro: se sigue buscando.
            // (El .srt que ya estuviera puesto nunca se toca: el de España queda aparte.)
            if fila.candidatoEspaña != nil {
                cambiar(id) { $0.estado = antes }
            } else {
                let final = ordenar(id, video, resultado, esEpisodio: esEpisodio, organizar: organizarlos, preferirLatino: latino)
                cambiar(id) { $0.estado = final }
            }
            return .soloEspaña
        case .desfasado:
            cambiar(id) { $0.estado = fila.terminada || fila.candidatoEspaña != nil ? antes : Self.traducir(resultado) }
            return .desfasado
        case .sinSubtitulos, .falló:
            cambiar(id) { $0.estado = antes }
            return .nada
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
        refrescarVersiones()
    }

    /// Qué filas ya tienen su versión de SubFix al lado (el MKV que se creó en esta sesión,
    /// aunque se llame distinto, o un «Nombre (SubFix).mkv» de antes).
    func refrescarVersiones() {
        for i in filas.indices {
            let fila = filas[i]
            if let mkv = fila.archivoListo, mkv != fila.url, mkv.pathExtension.lowercased() == "mkv",
               FileManager.default.fileExists(atPath: mkv.path) {
                filas[i].versionNueva = mkv
            } else {
                filas[i].versionNueva = Papelera.versionDeSubFix(de: fila.url)
            }
        }
    }

    /// Manda el video y sus .srt sueltos a la Papelera (se recuperan con «Devolver») y lo quita de la lista.
    public func aLaPapelera(_ id: UUID) {
        guard let fila = filas.first(where: { $0.id == id }),
              fila.estado != .procesando, fila.estado != .analizando else { return }
        do {
            let enviados = try Papelera.enviar(fila.url)
            descartadas.insert(fila.url.standardizedFileURL)
            filas.removeAll { $0.id == id }
            let subs = enviados.count - 1
            aviso = nil
            nota = "«\(fila.url.lastPathComponent)»" + (subs > 0 ? " y \(subs) subtítulo\(subs == 1 ? "" : "s")" : "")
                + " a la Papelera. Si te equivocaste, ábrela y usa «Devolver»."
        } catch {
            aviso = error.localizedDescription
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
        guard let fila = filas.first(where: { $0.id == id }), fila.estado != .procesando else { return }
        descartadas.insert(fila.url.standardizedFileURL)
        filas.removeAll { $0.id == id }
    }

    // MARK: Descargas

    /// Lo que el usuario quitó a mano: revisar Descargas no lo vuelve a traer (en esta sesión).
    private var descartadas: Set<URL> = []
    /// Lo que entró solo desde Descargas, para soltarlo si Organizar se lo lleva.
    private var desdeDescargas: Set<URL> = []

    /// La carpeta que «Subtítulos» revisa sola, si el usuario eligió una.
    /// Sin elegir (nil) usa la misma entrada de «Organizar».
    @Published public private(set) var carpetaPropia: URL? =
        Ajustes.almacen.string(forKey: "subfix.descargas").map(URL.init(fileURLWithPath:)) {
        didSet { Ajustes.almacen.set(carpetaPropia?.path, forKey: "subfix.descargas") }
    }

    /// Trae a la lista los videos de la carpeta de descargas (la propia o, si no hay,
    /// `porDefecto`, la de «Organizar»).
    /// Sólo videos: un .srt suelto ahí no se adopta solo. Salta lo que aún se está
    /// bajando, los «sample» y lo que el usuario ya quitó. Si un video que vino de
    /// aquí ya no está (lo movió Organizar) y no se está procesando, sale de la lista.
    public func revisarDescargas(_ porDefecto: URL?) {
        guard let carpeta = carpetaPropia ?? porDefecto else { return }
        filas.removeAll { fila in
            desdeDescargas.contains(fila.url.standardizedFileURL) && fila.estado != .procesando
                && !FileManager.default.fileExists(atPath: fila.url.path)
        }
        let contenido = (try? FileManager.default.contentsOfDirectory(
            at: carpeta, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let completas = contenido.filter { !Organizador.aMedioBajar($0) }
        let yaEstan = Set(filas.map { $0.url.standardizedFileURL })
        let nuevas = Motor.videos(en: completas)
            .map(\.standardizedFileURL)
            .filter { !yaEstan.contains($0) && !descartadas.contains($0) }
            .filter { !$0.deletingPathExtension().lastPathComponent.lowercased().contains("sample") }
            .map(Fila.init)
        desdeDescargas.formUnion(nuevas.map(\.url))
        filas.append(contentsOf: nuevas)
        for fila in nuevas { analizar(fila.id, fila.url) }
        refrescarVersiones()
    }

    /// Abre el selector para cambiar la carpeta que se revisa sola.
    public func elegirCarpetaDeDescargas(porDefecto: URL?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        panel.message = "¿Qué carpeta reviso para buscar películas y series sin subtítulo?"
        panel.directoryURL = carpetaPropia ?? porDefecto
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cambiarCarpeta(a: url, porDefecto: porDefecto)
    }

    /// Vuelve a revisar la misma carpeta que «Organizar».
    public func usarLaDeOrganizar(_ porDefecto: URL?) {
        cambiarCarpeta(a: nil, porDefecto: porDefecto)
    }

    /// Al cambiar de carpeta, lo que entró solo de la anterior y aún no se ha tocado
    /// sale de la lista (los archivos no se tocan); lo hecho o en marcha se queda.
    private func cambiarCarpeta(a nueva: URL?, porDefecto: URL?) {
        carpetaPropia = nueva
        let raiz = (nueva ?? porDefecto)?.standardizedFileURL.path ?? ""
        filas.removeAll { fila in
            let ruta = fila.url.standardizedFileURL
            let sinTocar = (fila.estado == .analizando || fila.estado == .listaParaProcesar) && fila.plan == nil
            return desdeDescargas.contains(ruta) && sinTocar && !ruta.path.hasPrefix(raiz + "/")
        }
        revisarDescargas(porDefecto)
    }

    /// «Reprocesar»: vuelve a buscar el subtítulo de esta fila sin vaciar la lista. Si ya
    /// tenía uno puesto, se marca como rechazado (no vuelve a salir, venga de donde venga)
    /// y se aparta como «.anterior» sólo cuando aparezca otro; si no aparece, se queda.
    public func reprocesar(_ id: UUID) {
        guard let fila = filas.first(where: { $0.id == id }),
              fila.estado != .procesando, fila.estado != .analizando else { return }
        let puesto = Motor.destinoSRT(de: fila.url)
        let huella = (try? TextoSRT.leer(puesto).texto).flatMap { TextoSRT.esSRT($0) ? Motor.huella($0) : nil }
        cambiar(id) { f in
            if let huella { f.descartados.insert(huella) }
            f.forzar = true   // también si sólo lo traía dentro: buscar otro igual
            f.estado = .listaParaProcesar
            f.candidatoEspaña = nil
            f.progreso = nil
        }
        if !trabajando { procesarTodo(solo: [id]) }
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
        descartadas.formUnion(filas.filter { $0.estado != .procesando }.map { $0.url.standardizedFileURL })
        filas.removeAll()
    }

    public var pendientes: [Fila] {
        // Una fila que falló al crear su MKV conserva el plan: se puede reintentar sin volver a armarlo.
        filas.filter { fila in
            if fila.estado == .listaParaProcesar { return motivoDeLista(fila) == nil }
            if case .fallada = fila.estado, fila.plan != nil { return true }
            return false
        }
    }

    /// Si ya no hay nada que hacerle (trae el subtítulo dentro, o un .srt bueno al lado), el porqué:
    /// la fila sale como «Lista» y no cuenta como pendiente. «Reprocesar» la fuerza igual.
    public func motivoDeLista(_ fila: Fila) -> String? {
        guard fila.estado == .listaParaProcesar, fila.plan == nil, fila.pistaElegida == nil, !fila.forzar,
              let diagnostico = fila.diagnostico else { return nil }
        return diagnostico.yaListo(preferirLatino: preferirLatino && usarRed, extraerDelArchivo: extraerDelArchivo)
    }

    public func procesarTodo(solo ids: [UUID]? = nil) {
        guard !trabajando else { return }
        trabajando = true
        let porHacer = pendientes.filter { ids?.contains($0.id) ?? true }
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
                        refrescarVersiones()
                    } catch {
                        cambiar(id) { $0.progreso = nil; $0.estado = .fallada(error.localizedDescription) }
                    }
                    continue
                }
                let opciones = Motor.Opciones(usarRed: red, forzar: fila.forzar,
                                              pistaPreferida: fila.pistaElegida,
                                              preferirLatino: latino, extraerDelArchivo: extraer,
                                              retenerEspaña: latino, descartados: fila.descartados)
                let resultado = await Motor.procesar(fila.url, opciones: opciones)
                var estado = ordenar(fila.id, fila.url, resultado,
                                     esEpisodio: fila.diagnostico?.esEpisodio == true,
                                     organizar: organizarlos, preferirLatino: latino)
                // Reprocesando: si no apareció otro, el de antes sigue puesto. Decirlo.
                if fila.forzar, !resultado.fueBien,
                   FileManager.default.fileExists(atPath: Motor.destinoSRT(de: fila.url).path) {
                    switch estado {
                    case .avisada(let t): estado = .avisada(t + " · sigue puesto el que tenía")
                    case .fallada(let t): estado = .fallada(t + " · sigue puesto el que tenía")
                    default: break
                    }
                }
                cambiar(fila.id) { $0.estado = estado; $0.forzar = false }
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
        case .desfasado(let origenes):
            let cuantos = origenes.components(separatedBy: ", ").count
            return .avisada(cuantos == 1
                ? "el que encontré no va sincronizado con este video (\(origenes)) — no lo puse"
                : "los \(cuantos) que encontré no van sincronizados con este video — no puse ninguno")
        case .falló(let motivo):
            return .fallada(motivo)
        }
    }
}
