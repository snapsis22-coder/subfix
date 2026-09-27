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

    /// Quedó en naranja: sin subtítulo, o sólo con el de España.
    public var avisa: Bool { if case .avisada = estado { return true } else { return false } }
    public var terminada: Bool { if case .hecha = estado { return true } else { return false } }
}

@MainActor
public final class Cola: ObservableObject {
    @Published public var filas: [Fila] = []
    @Published public var trabajando = false
    @Published public var usarRed = true
    @Published public var preferirLatino = true
    @Published public var organizar = false
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

    private func adoptar(_ subtitulos: [URL]) {
        // Primero los que avisaron que les falta; si ninguno casa, cualquiera.
        let avisadas = filas.filter { if case .avisada = $0.estado { return true } else { return false } }
        var pares = Motor.emparejar(subtitulos, con: avisadas.map(\.url))
        if pares.isEmpty { pares = Motor.emparejar(subtitulos, con: filas.map(\.url)) }

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
                let resultado = Motor.adoptar(par.subtitulo, para: par.video)
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
        let latino = preferirLatino
        let organizarlos = organizar

        Task {
            for fila in porHacer {
                cambiar(fila.id) { $0.estado = .procesando }
                let opciones = Motor.Opciones(usarRed: red, forzar: false,
                                              pistaPreferida: fila.pistaElegida,
                                              preferirLatino: latino)
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
        }
    }

    static let pedirSubdivx = "búscalo en Subdivx y arrastra aquí lo que bajes"

    static func traducir(_ resultado: Motor.Resultado, preferirLatino: Bool = true) -> Fila.Estado {
        switch resultado {
        case .listo(let origen, let lineas, let publicidad, let etiquetas, let depurados, let deEspaña):
            if preferirLatino, deEspaña {
                return .avisada("no conseguí latino: dejé el de España (\(origen)) · \(pedirSubdivx)")
            }
            var texto = "\(lineas) líneas · \(origen)"
            if publicidad > 0 { texto += " · \(publicidad) bloque(s) de publicidad fuera" }
            if etiquetas > 0 { texto += " · \(etiquetas) línea(s) con etiquetas de formato limpiadas" }
            if depurados > 0 { texto += " · \(depurados) línea(s) con caracteres basura depuradas" }
            return .hecha(texto)
        case .reparado(_, true) where preferirLatino, .yaEstaba(true) where preferirLatino:
            return .avisada("el .srt que tiene es de España · \(pedirSubdivx)")
        case .reparado(let codificacion, _):
            return .hecha("el .srt que ya estaba venía en \(codificacion) — corregido")
        case .yaEstaba:
            return .hecha("ya tenía subtítulo correcto")
        case .sinSubtitulos(let soloImagen):
            return .avisada(soloImagen
                ? "sólo trae subtítulos de imagen y no hay nada en internet · \(pedirSubdivx)"
                : "no encontré ningún subtítulo en español · \(pedirSubdivx)")
        case .falló(let motivo):
            return .fallada(motivo)
        }
    }
}
