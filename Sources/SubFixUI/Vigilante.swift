import Foundation
import SubFixKit
import UserNotifications

/// Vigila una carpeta y procesa sola cada película nueva que aparezca.
///
/// Repasa la carpeta cada 30 segundos en vez de usar FSEvents: una descarga
/// tarda minutos, así que media vuelta de reloj de retraso no se nota, y a
/// cambio no hay que lidiar con avisos a medio escribir del sistema de archivos.
@MainActor
public final class Vigilante: ObservableObject {

    @Published public var carpeta: URL? {
        didSet { UserDefaults.standard.set(carpeta?.path, forKey: "carpetaVigilada") }
    }
    @Published public var activo = false {
        didSet { activo ? arrancar() : detener() }
    }
    @Published public var historial: [Anotacion] = []
    @Published public var revisando = false

    public struct Anotacion: Identifiable {
        public let id = UUID()
        public let nombre: String
        public let cuando: Date
        public let texto: String
        public let bien: Bool
    }

    private var reloj: Timer?
    /// Lo ya visto, para no volver a mirar lo mismo cada media vuelta.
    private var atendidos: Set<String> = []

    public init() {
        if let guardada = UserDefaults.standard.string(forKey: "carpetaVigilada") {
            carpeta = URL(fileURLWithPath: guardada)
        }
    }

    private func arrancar() {
        guard carpeta != nil else { activo = false; return }
        pedirPermisoDeAvisos()
        reloj = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.revisar() }
        }
        Task { await revisar() }        // una primera pasada inmediata
    }

    private func detener() {
        reloj?.invalidate()
        reloj = nil
    }

    public func revisar() async {
        guard let carpeta, !revisando else { return }
        revisando = true
        defer { revisando = false }

        for video in Motor.videos(en: [carpeta]) {
            guard !atendidos.contains(video.path) else { continue }

            // Un archivo aún descargándose cambia de tamaño: hay que dejarlo en paz.
            guard estaQuieto(video) else { continue }

            let destino = Motor.destinoSRT(de: video)
            if FileManager.default.fileExists(atPath: destino.path),
               TextoSRT.estaBienFormado(destino) {
                atendidos.insert(video.path)
                continue
            }

            let resultado = await Motor.procesar(video)
            atendidos.insert(video.path)
            anotar(video, resultado)
        }
    }

    /// Dos medidas separadas por dos segundos: si el tamaño no se movió, la
    /// descarga terminó.
    private func estaQuieto(_ url: URL) -> Bool {
        func tamaño() -> Int {
            let atributos = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (atributos?[.size] as? Int) ?? 0
        }
        let antes = tamaño()
        guard antes > 0 else { return false }
        Thread.sleep(forTimeInterval: 2)
        return tamaño() == antes
    }

    private func anotar(_ video: URL, _ resultado: Motor.Resultado) {
        let estado = Cola.traducir(resultado)
        let texto = estado.detalle ?? ""
        historial.insert(Anotacion(nombre: video.lastPathComponent,
                                   cuando: Date(),
                                   texto: texto,
                                   bien: resultado.fueBien),
                         at: 0)
        if historial.count > 50 { historial.removeLast() }
        if resultado.fueBien { avisar(video.lastPathComponent) }
    }

    // MARK: - Avisos del sistema

    private func pedirPermisoDeAvisos() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func avisar(_ nombre: String) {
        let contenido = UNMutableNotificationContent()
        contenido.title = "Subtítulos listos"
        contenido.body = nombre
        contenido.sound = .default
        let peticion = UNNotificationRequest(identifier: UUID().uuidString,
                                             content: contenido, trigger: nil)
        UNUserNotificationCenter.current().add(peticion)
    }
}
