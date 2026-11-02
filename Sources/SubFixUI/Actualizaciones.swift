import AppKit
import Foundation
import SubFixKit
import SwiftUI

/// Lo que se ve de las actualizaciones: busca una vez al día al abrir (o cuando se pide
/// en el menú), avisa con una franja y sólo instala cuando el usuario pulsa «Actualizar».
/// Nunca se instala sola: cortaría un MKV o un lote de Organizar a la mitad.
///
/// La descarga la hace la app, no el navegador, así que la versión nueva no lleva la
/// marca de «descargado de internet» y macOS no vuelve a pedir «Abrir de todos modos».
@MainActor
public final class Actualizaciones: ObservableObject {

    public static let compartido = Actualizaciones()

    public enum Estado: Equatable {
        case quieto
        case buscando
        case disponible(VersionNueva)
        case descargando(VersionNueva, Double)
        case instalando(VersionNueva)
        case alDia
        case fallo(String)
    }

    @Published public private(set) var estado = Estado.quieto
    @Published public var buscarSola = UserDefaults.standard.object(forKey: "subfix.buscarActualizaciones") as? Bool ?? true {
        didSet { UserDefaults.standard.set(buscarSola, forKey: "subfix.buscarActualizaciones") }
    }

    private let claveUltima = "subfix.ultimaBusqueda"
    private let claveOmitida = "subfix.versionOmitida"

    /// Al abrir la ventana: como mucho una vez al día, y sin molestar si falla (sin internet).
    public func buscarSiToca() {
        guard buscarSola else { return }
        let ultima = UserDefaults.standard.object(forKey: claveUltima) as? Date ?? .distantPast
        guard Date().timeIntervalSince(ultima) > 20 * 3600 else { return }
        Task { await buscar(aMano: false) }
    }

    /// `aMano` = desde el menú: entonces sí dice «ya tienes la última» o el error.
    public func buscar(aMano: Bool) async {
        switch estado {
        case .buscando, .descargando, .instalando: return
        default: break
        }
        estado = .buscando
        do {
            let nueva = try await Actualizador.buscar()
            UserDefaults.standard.set(Date(), forKey: claveUltima)
            if let nueva, aMano || nueva.version != UserDefaults.standard.string(forKey: claveOmitida) {
                estado = .disponible(nueva)
            } else {
                estado = aMano ? .alDia : .quieto
            }
        } catch {
            estado = aMano ? .fallo(error.localizedDescription) : .quieto
        }
    }

    /// «Ahora no» para esta versión: no vuelve a avisar de ella sola (sí desde el menú).
    public func omitir() {
        if case .disponible(let v) = estado { UserDefaults.standard.set(v.version, forKey: claveOmitida) }
        estado = .quieto
    }

    public func cerrarAviso() { estado = .quieto }

    /// Baja, comprueba (hash de GitHub + mismo certificado), cambia la app y la reabre.
    public func actualizar() async {
        guard case .disponible(let version) = estado else { return }
        let instalada = Bundle.main.bundleURL
        if instalada.path.hasPrefix("/Volumes/") {
            estado = .fallo("SubFix se está abriendo desde el DMG. Arrástrala a Aplicaciones y actualiza desde ahí.")
            return
        }
        estado = .descargando(version, 0)
        do {
            let dmg = try await Actualizador.descargar(version) { avance in
                Task { @MainActor in
                    if case .descargando = self.estado { self.estado = .descargando(version, avance) }
                }
            }
            estado = .instalando(version)
            try await Task.detached {
                let nueva = try Actualizador.prepararEnTemporal(dmg: dmg, esperando: version.version,
                                                                comparandoCon: instalada)
                try Actualizador.instalar(nueva, en: instalada)
            }.value
            Actualizador.relanzar(instalada)
            NSApp.terminate(nil)
        } catch {
            estado = .fallo(error.localizedDescription)
        }
    }
}

// MARK: - La franja de aviso

/// Va bajo la cabecera, en cualquier pestaña. Sólo aparece si hay algo que decir.
struct AvisoDeActualizacion: View {
    @ObservedObject var modelo: Actualizaciones
    /// Procesando, organizando o vigilando: mejor no cerrar la app a la mitad.
    let ocupada: Bool
    @State private var viendoNotas = false

    var body: some View {
        switch modelo.estado {
        case .quieto, .buscando:
            EmptyView()
        case .disponible(let v):
            franja(icono: "arrow.down.circle.fill", color: Tema.morado,
                   texto: "SubFix \(v.version) ya está disponible (tienes la \(Actualizador.versionActual)).") {
                Button("Novedades") { viendoNotas.toggle() }
                    .buttonStyle(BotonSecundario(compacto: true))
                    .popover(isPresented: $viendoNotas, arrowEdge: .bottom) { notas(v) }
                Button("Ahora no") { modelo.omitir() }
                    .buttonStyle(BotonSecundario(compacto: true))
                    .help("No vuelve a avisar de esta versión. Puedes buscarla en el menú SubFix")
                Button { Task { await modelo.actualizar() } } label: {
                    Label("Actualizar", systemImage: "arrow.down.circle")
                }
                .buttonStyle(BotonPrincipal(compacto: true))
                .disabled(ocupada)
                .help(ocupada ? "Espera a que termine lo que está haciendo" : "Baja la versión nueva, la comprueba y reabre SubFix")
            }
        case .descargando(let v, let avance):
            franja(icono: "arrow.down.circle.fill", color: Tema.morado,
                   texto: "Bajando SubFix \(v.version)… \(Int(avance * 100)) %") {
                ProgressView(value: avance).frame(width: 160).tint(Tema.morado)
            }
        case .instalando(let v):
            franja(icono: "checkmark.shield.fill", color: Tema.verde,
                   texto: "Comprobando la firma e instalando SubFix \(v.version). Se abrirá sola en un momento…") {
                ProgressView().controlSize(.small)
            }
        case .alDia:
            franja(icono: "checkmark.circle.fill", color: Tema.verde,
                   texto: "Ya tienes la última versión (\(Actualizador.versionActual)).") {
                Button("Cerrar") { modelo.cerrarAviso() }.buttonStyle(BotonSecundario(compacto: true))
            }
        case .fallo(let motivo):
            franja(icono: "exclamationmark.triangle.fill", color: Tema.ambar,
                   texto: "No se pudo actualizar: \(motivo)") {
                Button("Cerrar") { modelo.cerrarAviso() }.buttonStyle(BotonSecundario(compacto: true))
            }
        }
    }

    private func franja<Botones: View>(icono: String, color: Color, texto: String,
                                       @ViewBuilder botones: () -> Botones) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icono).foregroundStyle(color).font(.system(size: 15))
            Text(texto)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Tema.tinta)
                .lineLimit(2)
            Spacer()
            botones()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Tema.tarjeta))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.35), lineWidth: 1))
        .shadow(color: color.opacity(0.15), radius: 8, y: 3)
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    private func notas(_ v: VersionNueva) -> some View {
        ScrollView {
            Text((try? AttributedString(markdown: v.notas, options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(v.notas))
                .font(.system(size: 12.5))
                .foregroundStyle(Tema.tinta)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(16)
        }
        .frame(width: 420, height: 260)
    }
}

// MARK: - Menú SubFix

/// «Buscar actualizaciones…» y el interruptor, debajo de «Acerca de SubFix».
public struct ComandosDeActualizacion: View {
    @ObservedObject var modelo = Actualizaciones.compartido
    public init() {}

    public var body: some View {
        Button("Buscar actualizaciones…") { Task { await modelo.buscar(aMano: true) } }
        Toggle("Buscar actualizaciones al abrir", isOn: $modelo.buscarSola)
    }
}
