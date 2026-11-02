import AppKit
import OrganizarKit
import Foundation
import UserNotifications

/// Una descarga en la lista. Es un struct dentro del modelo, no un objeto observable
/// aparte: la barra inferior decide a partir de todas las filas (lección de la Cola).
public struct Descarga: Identifiable, Equatable {
    public let id = UUID()
    public let examen: Examen
    /// Lo que se entendió del nombre, o lo que el usuario corrigió a mano.
    public var lectura: Lectura?
    public var incluida = true
    public var resultado: Resultado?

    public enum Resultado: Equatable {
        case hecho
        case fallo(String)
    }

    public init(examen: Examen) {
        self.examen = examen
        self.lectura = examen.lectura
    }
}

/// En qué punto está cada fila, para pintar su etiqueta.
public enum EstadoDeDescarga: Equatable {
    case listo, sinAño, noEntiendo, enOrden, choque(String), moviendo, hecho, fallo(String)

    /// Lo que el modo automático se atreve a mover sin preguntar.
    var esSeguro: Bool { self == .listo }
}

@MainActor
public final class Organizador: ObservableObject {

    @Published public var entrada: URL? { didSet { guardar(entrada, "entrada") } }
    @Published public var peliculas: URL? { didSet { guardar(peliculas, "peliculas") } }
    @Published public var series: URL? { didSet { guardar(series, "series") } }

    @Published public var filas: [Descarga] = []
    @Published public var moviendo: Set<UUID> = []
    @Published public var trabajando = false
    @Published public var ultimoLote: [Movimiento] = []
    @Published public var mensaje: String?
    @Published public var automatico = false {
        didSet {
            guard !demo else { return }     // los retratos no tienen bundle para avisos
            UserDefaults.standard.set(automatico, forKey: "organizar.automatico")
            automatico ? arrancarVigilancia() : detenerVigilancia()
        }
    }

    private let demo: Bool
    private var reloj: Timer?
    /// Tamaño de cada descarga en la vuelta anterior: si no cambió, ya terminó de bajar.
    private var tamañosPrevios: [String: Int64] = [:]

    public init(demo: Bool = false) {
        self.demo = demo
        guard !demo else { return }
        entrada = Self.leer("entrada")
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        peliculas = Self.leer("peliculas") ?? Self.siExiste("/Volumes/DATOS/Peliculas")
        series = Self.leer("series") ?? Self.siExiste("/Volumes/DATOS/Series")
        if UserDefaults.standard.bool(forKey: "organizar.automatico") { automatico = true }
    }

    private static func siExiste(_ ruta: String) -> URL? {
        FileManager.default.fileExists(atPath: ruta) ? URL(fileURLWithPath: ruta) : nil
    }

    private func guardar(_ url: URL?, _ clave: String) {
        guard !demo else { return }
        UserDefaults.standard.set(url?.path, forKey: "organizar.\(clave)")
    }

    /// La carpeta guardada; si aún no hay, la que se eligió en la app Cartelera, que
    /// vivía aparte antes de entrar en SubFix.
    private static func leer(_ clave: String) -> URL? {
        let ruta = UserDefaults.standard.string(forKey: "organizar.\(clave)")
            ?? UserDefaults(suiteName: "com.snapsis.cartelera")?.string(forKey: clave)
        return ruta.map(URL.init(fileURLWithPath:))
    }

    public var bibliotecas: Bibliotecas? {
        guard let peliculas, let series else { return nil }
        return Bibliotecas(peliculas: peliculas, series: series)
    }

    // MARK: - Lo que se ve

    public func estado(de fila: Descarga) -> EstadoDeDescarga {
        if moviendo.contains(fila.id) { return .moviendo }
        switch fila.resultado {
        case .hecho?: return .hecho
        case .fallo(let motivo)?: return .fallo(motivo)
        case nil: break
        }
        guard let lectura = fila.lectura else { return .noEntiendo }
        guard let bibliotecas else { return .listo }
        let movimientos = Planificador.movimientos(fila.examen, como: lectura, en: bibliotecas)
        switch Planificador.diagnosticar(movimientos, lectura: lectura) {
        case .enOrden: return .enOrden
        case .listo: return .listo
        case .sinAño: return .sinAño
        case .choque(let nombre): return .choque(nombre)
        }
    }

    /// Las filas que vale la pena mostrar: lo que ya está en orden no estorba.
    public var visibles: [Descarga] { filas.filter { estado(de: $0) != .enOrden } }
    public var enOrden: Int { filas.count - visibles.count }

    /// Lo que se movería al pulsar «Organizar». Las películas sin año sí entran si el
    /// usuario las deja marcadas: es su decisión.
    public var porMover: [Descarga] {
        filas.filter { fila in
            guard fila.incluida else { return false }
            let e = estado(de: fila)
            return e == .listo || e == .sinAño
        }
    }

    /// «Películas › Verity (2026)», para enseñar el destino sin la ruta completa.
    public func rutaCorta(de fila: Descarga) -> [String] {
        guard let lectura = fila.lectura else { return [] }
        switch lectura {
        case .pelicula: return [peliculas?.lastPathComponent ?? "Películas", lectura.carpeta]
        case .serie: return [series?.lastPathComponent ?? "Series", lectura.carpeta, lectura.carpetaDeTemporada!]
        }
    }

    // MARK: - Acciones

    /// Vuelve a mirar la carpeta de entrada. Lo ya hecho en esta sesión se queda a la vista.
    public func revisarEntrada() {
        guard let entrada else { return }
        let hechas = filas.filter { $0.resultado != nil }
        let nuevas = Planificador.examinarCarpeta(entrada).map(Descarga.init)
        filas = hechas + nuevas
        mensaje = nil
    }

    /// Lo arrastrado a la ventana, venga de donde venga.
    public func agregar(_ urls: [URL]) {
        let yaEstan = Set(filas.map { $0.examen.origen.standardizedFileURL })
        let nuevas = urls.filter { !yaEstan.contains($0.standardizedFileURL) }
            .compactMap(Planificador.examinar).map(Descarga.init)
        filas.append(contentsOf: nuevas)
        if nuevas.isEmpty, !urls.isEmpty { mensaje = "No encontré videos en lo que soltaste" }
    }

    public func corregir(_ id: UUID, a lectura: Lectura) {
        guard let i = filas.firstIndex(where: { $0.id == id }) else { return }
        filas[i].lectura = lectura
        filas[i].incluida = true
    }

    public func alternar(_ id: UUID) {
        guard let i = filas.firstIndex(where: { $0.id == id }) else { return }
        filas[i].incluida.toggle()
    }

    public func quitar(_ id: UUID) {
        filas.removeAll { $0.id == id }
    }

    public func limpiarHechas() {
        filas.removeAll { $0.resultado == .hecho }
    }

    /// Mueve todo lo marcado, una fila a la vez y fuera del hilo principal: entre
    /// discos distintos un 4K tarda en copiarse.
    public func organizar(_ elegidas: [Descarga]? = nil) async {
        guard let bibliotecas, !trabajando else { return }
        let lote = elegidas ?? porMover
        guard !lote.isEmpty else { return }
        trabajando = true
        mensaje = nil
        var hechos: [Movimiento] = []
        var bien = 0

        for fila in lote {
            guard let lectura = fila.lectura else { continue }
            moviendo.insert(fila.id)
            let movimientos = Planificador.movimientos(fila.examen, como: lectura, en: bibliotecas)
            let resultado = await Task.detached { Planificador.ejecutar(movimientos) }.value
            moviendo.remove(fila.id)
            hechos += resultado.hechos
            if let i = filas.firstIndex(where: { $0.id == fila.id }) {
                if let falla = resultado.falla {
                    filas[i].resultado = .fallo(falla.localizedDescription)
                } else {
                    filas[i].resultado = .hecho
                    bien += 1
                }
            }
        }

        ultimoLote = hechos
        trabajando = false
        if bien > 0 {
            mensaje = bien == 1 ? "Listo: 1 descarga organizada" : "Listo: \(bien) descargas organizadas"
            if automatico { avisar("SubFix organizó \(bien == 1 ? "1 descarga" : "\(bien) descargas")",
                                   lote.compactMap { $0.lectura?.carpeta }.joined(separator: ", ")) }
        }
    }

    /// Devuelve a su sitio todo lo del último «Organizar».
    public func deshacer() async {
        let lote = ultimoLote
        guard !lote.isEmpty, !trabajando else { return }
        trabajando = true
        let falla = await Task.detached { Planificador.deshacer(lote) }.value
        trabajando = false
        ultimoLote = []
        if let falla {
            mensaje = falla.localizedDescription
        } else {
            mensaje = "Deshecho: todo volvió a su sitio"
            filas.removeAll { $0.resultado == .hecho }
            revisarEntrada()
        }
    }

    // MARK: - Modo automático

    /// Repasa la entrada cada 30 segundos, igual que la pestaña Vigilar: una
    /// descarga tarda minutos, así que medio minuto de retraso no se nota.
    private func arrancarVigilancia() {
        guard entrada != nil else { automatico = false; return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        reloj = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.vuelta() }
        }
        Task { await vuelta() }
    }

    private func detenerVigilancia() {
        reloj?.invalidate()
        reloj = nil
        tamañosPrevios = [:]
    }

    private func vuelta() async {
        guard automatico, !trabajando else { return }
        revisarEntrada()
        var quietas: [Descarga] = []
        var tamaños: [String: Int64] = [:]
        for fila in filas where fila.resultado == nil && estado(de: fila).esSeguro {
            let ruta = fila.examen.origen.path
            let tamaño = Self.tamaño(de: fila.examen.origen)
            tamaños[ruta] = tamaño
            // Solo lo que no cambió de tamaño desde la vuelta anterior y no tiene
            // pedazos a medio bajar.
            if let previo = tamañosPrevios[ruta], previo == tamaño, !Self.aMedioBajar(fila.examen.origen) {
                quietas.append(fila)
            }
        }
        tamañosPrevios = tamaños
        if !quietas.isEmpty { await organizar(quietas) }
    }

    nonisolated static func tamaño(de url: URL) -> Int64 {
        let claves: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        guard let valores = try? url.resourceValues(forKeys: claves) else { return 0 }
        if valores.isDirectory != true { return Int64(valores.fileSize ?? 0) }
        var total: Int64 = 0
        let recorrido = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        while let hijo = recorrido?.nextObject() as? URL {
            total += Int64((try? hijo.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    nonisolated static func aMedioBajar(_ url: URL) -> Bool {
        let pedazos: Set<String> = ["part", "crdownload", "download", "!qb", "!ut", "tmp", "partial"]
        if pedazos.contains(url.pathExtension.lowercased()) { return true }
        let recorrido = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        while let hijo = recorrido?.nextObject() as? URL {
            if pedazos.contains(hijo.pathExtension.lowercased()) { return true }
        }
        return false
    }

    private func avisar(_ titulo: String, _ cuerpo: String) {
        let contenido = UNMutableNotificationContent()
        contenido.title = titulo
        contenido.body = cuerpo
        contenido.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: contenido, trigger: nil))
    }

    // MARK: - Elegir carpetas

    public enum Cual { case entrada, peliculas, series }

    public func elegir(_ cual: Cual) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Elegir"
        switch cual {
        case .entrada: panel.message = "¿Dónde caen tus descargas?"; panel.directoryURL = entrada
        case .peliculas: panel.message = "¿Dónde guardas las películas?"; panel.directoryURL = peliculas
        case .series: panel.message = "¿Dónde guardas las series?"; panel.directoryURL = series
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch cual {
        case .entrada: entrada = url; revisarEntrada()
        case .peliculas: peliculas = url
        case .series: series = url
        }
    }
}
