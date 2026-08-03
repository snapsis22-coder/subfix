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
    public let url: URL

    public internal(set) var diagnostico: Motor.Diagnostico?
    var estado: Estado = .analizando
    var pistaElegida: Int?

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
            && izquierda.pistaElegida == derecha.pistaElegida
    }

    var nombre: String { url.lastPathComponent }
}

@MainActor
public final class Cola: ObservableObject {
    @Published public var filas: [Fila] = []
    @Published public var trabajando = false
    @Published public var usarRed = true
    @Published public var mensajeDeHerramientas: String?

    public init() {
        let faltan = Herramientas.faltantes
        if !faltan.isEmpty {
            mensajeDeHerramientas = "Falta \(faltan.joined(separator: " y ")). Instálalo con:  brew install ffmpeg"
        }
    }

    public func agregar(_ rutas: [URL]) {
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

    public func vaciar() {
        filas.removeAll()
    }

    public var pendientes: [Fila] {
        filas.filter { $0.estado == .listaParaProcesar }
    }

    public func procesarTodo() {
        guard !trabajando else { return }
        trabajando = true
        let porHacer = pendientes
        let red = usarRed

        Task {
            for fila in porHacer {
                cambiar(fila.id) { $0.estado = .procesando }
                let opciones = Motor.Opciones(usarRed: red, forzar: false,
                                              pistaPreferida: fila.pistaElegida)
                let resultado = await Motor.procesar(fila.url, opciones: opciones)
                cambiar(fila.id) { $0.estado = Self.traducir(resultado) }
            }
            Motor.limpiarFantasmas(en: Set(porHacer.map { $0.url.deletingLastPathComponent() }))
            trabajando = false
        }
    }

    static func traducir(_ resultado: Motor.Resultado) -> Fila.Estado {
        switch resultado {
        case .listo(let origen, let lineas, let publicidad):
            var texto = "\(lineas) líneas · \(origen)"
            if publicidad > 0 { texto += " · \(publicidad) bloque(s) de publicidad fuera" }
            return .hecha(texto)
        case .reparado(let codificacion):
            return .hecha("el .srt que ya estaba venía en \(codificacion) — corregido")
        case .yaEstaba:
            return .hecha("ya tenía subtítulo correcto")
        case .sinSubtitulos(let soloImagen):
            return .avisada(soloImagen
                ? "sólo trae subtítulos de imagen y no hay nada en OpenSubtitles — haría falta OCR"
                : "no se encontró ningún subtítulo en español")
        case .falló(let motivo):
            return .fallada(motivo)
        }
    }
}
