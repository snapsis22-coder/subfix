import SubFixKit
import SwiftUI
import UniformTypeIdentifiers

public struct VistaPrincipal: View {
    @StateObject private var cola = Cola()
    @StateObject private var vigilante = Vigilante()
    @State private var pestaña = Pestaña.peliculas

    enum Pestaña: String, CaseIterable {
        case peliculas = "Películas"
        case vigilancia = "Vigilar carpeta"

        var icono: String {
            switch self {
            case .peliculas: return "film.stack"
            case .vigilancia: return "eye"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pestaña) {
                ForEach(Pestaña.allCases, id: \.self) { p in
                    Label(p.rawValue, systemImage: p.icono).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            switch pestaña {
            case .peliculas: VistaPeliculas(cola: cola)
            case .vigilancia: VistaVigilancia(vigilante: vigilante)
            }
        }
        .frame(minWidth: 620, minHeight: 460)
        .overlay(alignment: .bottom) {
            if let mensaje = cola.mensajeDeHerramientas {
                AvisoDeHerramientas(mensaje: mensaje)
            }
        }
    }
}

// MARK: - Películas

struct VistaPeliculas: View {
    @ObservedObject var cola: Cola
    @State private var encima = false

    var body: some View {
        VStack(spacing: 0) {
            if cola.filas.isEmpty {
                ZonaVacia(encima: encima)
            } else {
                List {
                    ForEach(cola.filas) { fila in
                        FilaDePelicula(fila: fila) { indice in
                            cola.elegirPista(fila.id, indice: indice)
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            barraInferior
        }
        .dropDestination(for: URL.self) { rutas, _ in
            cola.agregar(rutas)
            return true
        } isTargeted: { encima = $0 }
        .animation(.easeInOut(duration: 0.15), value: encima)
    }

    private var barraInferior: some View {
        HStack(spacing: 12) {
            Toggle("Buscar en OpenSubtitles", isOn: $cola.usarRed)
                .toggleStyle(.checkbox)
                .help("Cuando la película no trae subtítulo de texto, se busca uno en internet")

            Spacer()

            if !cola.filas.isEmpty {
                Button("Vaciar") { cola.vaciar() }
                    .disabled(cola.trabajando)
            }

            Button {
                cola.procesarTodo()
            } label: {
                if cola.trabajando {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Procesando…")
                    }
                } else {
                    Text(cola.pendientes.isEmpty
                         ? "Procesar"
                         : "Procesar \(cola.pendientes.count) película\(cola.pendientes.count == 1 ? "" : "s")")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(cola.pendientes.isEmpty || cola.trabajando)
        }
        .padding(12)
    }
}

struct ZonaVacia: View {
    let encima: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(encima ? Color.accentColor : .secondary)
            Text("Arrastra películas o una carpeta")
                .font(.title3)
            Text("Deja el .srt listo para el Samsung: mismo nombre, UTF-8 con BOM y CRLF")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(encima ? Color.accentColor : Color.secondary.opacity(0.35))
                .padding(18)
        }
    }
}

struct FilaDePelicula: View {
    let fila: Fila
    let elegirPista: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: fila.estado.icono)
                .foregroundStyle(fila.estado.color)
                .font(.title3)
                .frame(width: 22)
                .symbolEffect(.pulse, isActive: fila.estado == .procesando)

            VStack(alignment: .leading, spacing: 3) {
                Text(fila.nombre)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fila.url.path)

                Text(fila.estado.detalle ?? fila.diagnostico?.plan ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let diagnostico = fila.diagnostico, diagnostico.pistas.filter(\.esTexto).count > 1,
               fila.estado == .listaParaProcesar {
                selectorDePista(diagnostico)
            }
        }
        .padding(.vertical, 4)
    }

    /// Cuando hay varias pistas de texto se puede cambiar la elegida: es la
    /// decisión que el motor no debería tomar solo.
    private func selectorDePista(_ diagnostico: Motor.Diagnostico) -> some View {
        Menu {
            ForEach(diagnostico.pistas.filter(\.esTexto)) { pista in
                Button {
                    elegirPista(pista.indice)
                } label: {
                    let elegida = (fila.pistaElegida ?? diagnostico.elegida?.indice) == pista.indice
                    Label(pista.resumen, systemImage: elegida ? "checkmark" : "")
                }
            }
        } label: {
            Label("Pista", systemImage: "captions.bubble")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Elegir otra pista de subtítulos")
    }
}

// MARK: - Vigilancia

struct VistaVigilancia: View {
    @ObservedObject var vigilante: Vigilante
    @State private var eligiendoCarpeta = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vigilante.carpeta?.path ?? "Ninguna carpeta elegida")
                                .lineLimit(1)
                                .truncationMode(.head)
                                .foregroundStyle(vigilante.carpeta == nil ? .secondary : .primary)
                            Text("Se revisa cada 30 segundos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Elegir…") { eligiendoCarpeta = true }
                    }

                    Toggle("Vigilar esta carpeta", isOn: $vigilante.activo)
                        .disabled(vigilante.carpeta == nil)
                } header: {
                    Text("Carpeta de descargas")
                }
            }
            .formStyle(.grouped)

            if vigilante.historial.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: vigilante.activo ? "eye" : "eye.slash")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(vigilante.activo
                         ? "Vigilando. Las películas nuevas se procesarán solas."
                         : "La vigilancia está apagada.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vigilante.historial) { anotacion in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: anotacion.bien ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(anotacion.bien ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(anotacion.nombre).lineLimit(1).truncationMode(.middle)
                            Text(anotacion.texto).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text(anotacion.cuando, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }
        }
        .fileImporter(isPresented: $eligiendoCarpeta, allowedContentTypes: [.folder]) { resultado in
            if case .success(let url) = resultado { vigilante.carpeta = url }
        }
    }
}

// MARK: - Aviso

struct AvisoDeHerramientas: View {
    let mensaje: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(mensaje).font(.callout)
            Spacer()
        }
        .padding(10)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
    }
}
