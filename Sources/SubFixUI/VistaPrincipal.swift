import AppKit
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
        .frame(minWidth: 760, minHeight: 460)
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
    @State private var paraMKV: Fila?

    var body: some View {
        VStack(spacing: 0) {
            if cola.filas.isEmpty {
                ZonaVacia(encima: encima, explorar: explorar)
            } else {
                List {
                    ForEach(cola.filas) { fila in
                        FilaDePelicula(fila: fila, preferirLatino: cola.preferirLatino && cola.usarRed,
                                       elegirPista: { indice in cola.elegirPista(fila.id, indice: indice) },
                                       crearMKV: { paraMKV = fila })
                    }
                }
                .listStyle(.inset)
            }

            if let aviso = cola.aviso {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(aviso).font(.callout)
                    Spacer()
                    Button("Cerrar") { cola.aviso = nil }.buttonStyle(.borderless)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.orange.opacity(0.08))
            }
            Divider()
            barraInferior
        }
        .dropDestination(for: URL.self) { rutas, _ in
            cola.agregar(rutas)
            return true
        } isTargeted: { encima = $0 }
        .animation(.easeInOut(duration: 0.15), value: encima)
        .sheet(item: $paraMKV) { fila in
            HojaDeMKV(video: fila.url)
        }
    }

    private func explorar() {
        let panel = NSOpenPanel()
        panel.title = "Elegir películas, carpetas o subtítulos"
        panel.prompt = "Añadir"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { cola.agregar(panel.urls) }
    }

    private var barraInferior: some View {
        HStack(spacing: 12) {
            Toggle("Buscar en OpenSubtitles", isOn: $cola.usarRed)
                .toggleStyle(.checkbox)
                .help("Cuando la película no trae subtítulo de texto, se busca uno en internet")

            Toggle("Preferir latino", isOn: $cola.preferirLatino)
                .toggleStyle(.checkbox)
                .help("En las series se busca primero el latino en Addic7ed. Si al final sólo hay "
                      + "español de España o nada, la fila avisa en naranja para buscarlo en Subdivx")

            Toggle("Carpeta por capítulo", isOn: $cola.organizar)
                .toggleStyle(.checkbox)
                .help("Mueve cada capítulo con su .srt a una subcarpeta propia, p. ej. «Ted Lasso S01E01»")

            Spacer()

            Button("Explorar…", action: explorar)
                .disabled(cola.trabajando)
                .help("Elegir películas, carpetas o el .zip/.srt de Subdivx sin arrastrar")

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
    let explorar: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(encima ? Color.accentColor : .secondary)
            Text("Arrastra películas o una carpeta")
                .font(.title3)
            Text("Deja el .srt listo para el Samsung: mismo nombre, UTF-8 con BOM y CRLF.\n"
                 + "También acepta el .zip, .rar o .srt que bajes de Subdivx.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Explorar…", action: explorar)
                .controlSize(.large)
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
    let preferirLatino: Bool
    let elegirPista: (Int) -> Void
    let crearMKV: () -> Void

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

                Text(fila.estado.detalle ?? fila.diagnostico?.plan(preferirLatino: preferirLatino) ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if case .avisada = fila.estado {
                Button {
                    buscarEnSubdivx()
                } label: {
                    Label("Subdivx", systemImage: "magnifyingglass")
                }
                .help("Abre Subdivx y copia «\(Motor.busquedaSubdivx(para: fila.url))» para pegarla en el buscador. "
                      + "Luego arrastra aquí lo que bajes")
            }

            if fila.terminada || fila.avisa {
                Button(action: crearMKV) {
                    Label("MKV limpio…", systemImage: "film")
                }
                .help("Crea un .mkv nuevo con los audios que elijas y este subtítulo como única pista de texto. "
                      + "El original no se toca")
            }

            if let diagnostico = fila.diagnostico, diagnostico.pistas.filter(\.esTexto).count > 1,
               fila.estado == .listaParaProcesar {
                selectorDePista(diagnostico)
            }
        }
        .padding(.vertical, 4)
    }

    /// Subdivx no deja que un programa busque por su cuenta (Cloudflare), así que
    /// la búsqueda la hace el usuario: se le deja copiada y se abre la página.
    private func buscarEnSubdivx() {
        let tablero = NSPasteboard.general
        tablero.clearContents()
        tablero.setString(Motor.busquedaSubdivx(para: fila.url), forType: .string)
        NSWorkspace.shared.open(URL(string: "https://www.subdivx.com/")!)
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

// MARK: - MKV limpio

/// Elegir qué audios se quedan y crear el .mkv nuevo con el subtítulo de SubFix.
struct HojaDeMKV: View {
    let video: URL
    @Environment(\.dismiss) private var cerrar

    @State private var audios: [PistaDeAudio] = []
    @State private var marcados: Set<Int> = []
    @State private var leyendo = true
    @State private var trabajando = false
    @State private var resultado: URL?
    @State private var error: String?

    private var subtitulo: URL { Motor.destinoSRT(de: video) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MKV limpio").font(.title2.bold())
            Text(video.lastPathComponent)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)

            GroupBox("Audios que se quedan") {
                if leyendo {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(8)
                } else if audios.isEmpty {
                    Text("No encontré pistas de audio.").foregroundStyle(.secondary).padding(8)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(audios) { audio in
                            Toggle(audio.resumen, isOn: Binding(
                                get: { marcados.contains(audio.indice) },
                                set: { activo in
                                    if activo { marcados.insert(audio.indice) } else { marcados.remove(audio.indice) }
                                }))
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }

            Text("Se quitan todos los subtítulos del original y queda solo este .srt (español, UTF-8). "
                 + "El video no se recodifica. Se crea «\(Remux.destino(para: video).lastPathComponent)» "
                 + "al lado; el original queda intacto.")
                .font(.callout).foregroundStyle(.secondary)

            if let error {
                Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout)
            }
            if let resultado {
                Label("Listo: \(resultado.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            }

            HStack {
                if let resultado {
                    Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([resultado]) }
                }
                Spacer()
                Button(resultado == nil ? "Cancelar" : "Cerrar") { cerrar() }
                    .disabled(trabajando)
                if resultado == nil {
                    Button {
                        crear()
                    } label: {
                        if trabajando {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Creando…") }
                        } else {
                            Text("Crear MKV")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trabajando || marcados.isEmpty || leyendo)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { await leer() }
    }

    private func leer() async {
        let url = video
        let encontrados = await Task.detached { (try? Sondeo.audios(de: url)) ?? [] }.value
        audios = encontrados
        // Lo habitual: quedarse con el inglés. Si no hay, todo, para no dejar mudo el archivo.
        let ingles = encontrados.filter(\.esIngles)
        marcados = Set((ingles.isEmpty ? encontrados : ingles).map(\.indice))
        leyendo = false
    }

    private func crear() {
        trabajando = true
        error = nil
        let origen = video, srt = subtitulo, elegidos = audios.map(\.indice).filter(marcados.contains)
        Task {
            do {
                resultado = try await Task.detached(priority: .userInitiated) {
                    try Remux.hacer(video: origen, subtitulo: srt, audios: elegidos)
                }.value
            } catch {
                self.error = error.localizedDescription
            }
            trabajando = false
        }
    }
}
