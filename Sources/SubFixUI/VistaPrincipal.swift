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
            HojaDeMKV(video: fila.url, planActual: fila.plan,
                      pendiente: fila.estado == .listaParaProcesar || fila.plan != nil,
                      alGuardar: { cola.guardarPlan(fila.id, $0) },
                      alCrear: { cola.mkvCreado(fila.id, $0) })
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
                HStack(spacing: 10) {
                    Text(fila.nombre)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(fila.url.path)
                    if fila.terminada { SelloListo().id(fila.id) }
                }

                Text(fila.estado.detalle ?? fila.plan?.resumen
                     ?? fila.diagnostico?.plan(preferirLatino: preferirLatino) ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if fila.estado == .procesando, let avance = fila.progreso {
                    BarraVerde(fraccion: avance, inicio: fila.inicioDeProgreso)
                        .frame(maxWidth: 420)
                        .padding(.top, 2)
                }
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

            if !fila.terminada, fila.avisa || fila.estado == .listaParaProcesar || fila.plan != nil {
                Button(action: crearMKV) {
                    Label(fila.plan == nil ? "Pistas…" : "Pistas ✓", systemImage: "slider.horizontal.3")
                }
                .help("Elige qué audios y subtítulos van en un MKV nuevo (puedes añadir un .srt). "
                      + "«Procesar» lo crea; el original no se toca")
            }

            if let diagnostico = fila.diagnostico, diagnostico.pistas.filter(\.esTexto).count > 1,
               fila.estado == .listaParaProcesar {
                selectorDePista(diagnostico)
            }

            if fila.terminada {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([archivoParaMostrar])
                } label: {
                    Label("Mostrar", systemImage: "folder")
                }
                .help("Mostrar «\(archivoParaMostrar.lastPathComponent)» en el Finder")
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 54)   // sitio para que el sello llegue grande sin que la fila lo recorte
    }

    /// El MKV recién creado; si no hubo, el .srt que quedó junto a la película; si tampoco, la película.
    private var archivoParaMostrar: URL {
        if let listo = fila.archivoListo, FileManager.default.fileExists(atPath: listo.path) { return listo }
        let srt = Motor.destinoSRT(de: fila.url)
        return FileManager.default.fileExists(atPath: srt.path) ? srt : fila.url
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

// MARK: - Pistas del MKV

/// Armar el MKV a medida: qué audios, qué subtítulos del archivo y qué .srt añadidos.
/// Se puede guardar como plan (lo crea «Procesar») o crear en el acto. Nunca deja un
/// .srt suelto a menos que se pida con «Extraer .srt».
struct HojaDeMKV: View {
    let video: URL
    let planActual: PlanDeMKV?
    let pendiente: Bool
    let alGuardar: (PlanDeMKV?) -> Void
    let alCrear: (URL) -> Void
    @Environment(\.dismiss) private var cerrar

    @State private var audios: [PistaDeAudio] = []
    @State private var subtitulos: [Pista] = []
    @State private var audiosMarcados: Set<Int> = []
    @State private var subsMarcados: Set<Int> = []
    @State private var externos: [URL] = []
    @State private var externosMarcados: Set<URL> = []
    @State private var nombre = ""
    @State private var nombreInicial = ""
    @State private var idiomasAudio: [Int: Idioma] = [:]
    @State private var idiomasSubs: [Int: Idioma] = [:]
    @State private var idiomasExternos: [URL: Idioma] = [:]
    @State private var leyendo = true
    @State private var trabajando = false
    @State private var resultado: URL?
    @State private var error: String?
    @State private var aviso: String?
    @StateObject private var avance = Avance()

    private var srtJunto: URL { Motor.destinoSRT(de: video) }

    private var plan: PlanDeMKV {
        PlanDeMKV(audios: audios.map(\.indice).filter(audiosMarcados.contains),
                  subtitulosDelArchivo: subtitulos.filter { subsMarcados.contains($0.indice) },
                  añadidos: externos.filter(externosMarcados.contains),
                  nombre: nombre == nombreInicial ? nil : Remux.nombreLimpio(nombre),
                  idiomasDeAudio: idiomasAudio.filter { audiosMarcados.contains($0.key) },
                  idiomasDeSubtitulo: idiomasSubs.filter { subsMarcados.contains($0.key) },
                  idiomasDeAñadidos: idiomasExternos)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pistas del MKV").font(.title2.bold())
            Text(video.lastPathComponent)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)

            HStack(spacing: 6) {
                Text("Nombre del archivo nuevo")
                TextField("", text: $nombre)
                    .textFieldStyle(.roundedBorder)
                Text(".mkv").foregroundStyle(.secondary)
            }
            .help("Se crea junto a la película. Si ya existe un archivo con ese nombre, se añade «(2)»")

            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            GroupBox("Audios") {
                if leyendo {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(8)
                } else if audios.isEmpty {
                    Text("No encontré pistas de audio.").foregroundStyle(.secondary).padding(8)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(audios) { audio in
                            HStack {
                                marca(audio.resumen, audiosMarcados.contains(audio.indice)) {
                                    alternar(&audiosMarcados, audio.indice, $0)
                                }
                                Spacer(minLength: 0)
                                selectorDeIdioma(Binding(get: { idiomasAudio[audio.indice] },
                                                         set: { idiomasAudio[audio.indice] = $0 }),
                                                 sinCambios: audio.sinIdioma ? "Sin especificar"
                                                                             : "Como está (\(audio.idioma ?? ""))")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }

            GroupBox("Subtítulos que trae el archivo") {
                if subtitulos.isEmpty {
                    Text(leyendo ? "Leyendo…" : "No trae subtítulos.").foregroundStyle(.secondary).padding(8)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(subtitulos) { pista in
                            HStack {
                                marca(pista.resumen, subsMarcados.contains(pista.indice)) {
                                    alternar(&subsMarcados, pista.indice, $0)
                                }
                                Spacer(minLength: 0)
                                selectorDeIdioma(Binding(get: { idiomasSubs[pista.indice] },
                                                         set: { idiomasSubs[pista.indice] = $0 }),
                                                 sinCambios: pista.sinIdioma ? "Sin especificar"
                                                                             : "Como está (\(pista.idioma ?? ""))")
                                if pista.esTexto {
                                    Button("Extraer .srt") { extraer(pista) }
                                        .controlSize(.small)
                                        .disabled(trabajando)
                                        .help("Guarda esta pista, limpia y lista para el TV, como «\(srtJunto.lastPathComponent)»")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }

            GroupBox("Subtítulos añadidos") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(externos, id: \.self) { url in
                        HStack {
                            marca(url.lastPathComponent, externosMarcados.contains(url)) {
                                alternar(&externosMarcados, url, $0)
                            }
                            Spacer(minLength: 0)
                            selectorDeIdioma(Binding(get: { idiomasExternos[url] ?? .español },
                                                     set: { idiomasExternos[url] = $0 ?? .español }),
                                             sinCambios: nil)
                        }
                    }
                    Button("Añadir un .srt, .zip o .rar…") { añadirExterno() }
                        .help("Por ejemplo, el .zip que bajaste de Subdivx")
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }

            Text("Sin recodificar; se crea al lado y el original queda intacto. Los .srt añadidos se limpian y "
                 + "van en UTF-8. Si una pista dice «Sin especificar», elige su idioma de la lista.")
                .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.trailing, 12)   // aire para la barra de desplazamiento
            }

            if let aviso { Label(aviso, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
            if trabajando, avance.mostrar {
                BarraVerde(fraccion: avance.fraccion, inicio: avance.inicio)
            }
            if let error { Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout) }
            if let resultado {
                Label("Listo: \(resultado.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            }

            HStack {
                if let resultado {
                    Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([resultado]) }
                } else if planActual != nil {
                    Button("Quitar el plan") { alGuardar(nil); cerrar() }
                        .help("«Procesar» volverá a extraer el .srt como siempre")
                }
                Spacer()
                Button(resultado == nil ? "Cancelar" : "Cerrar") { cerrar() }
                    .disabled(trabajando)
                if resultado == nil {
                    if pendiente {
                        Button("Guardar para Procesar") { alGuardar(plan); cerrar() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(trabajando || leyendo || audiosMarcados.isEmpty)
                    }
                    Button {
                        crear()
                    } label: {
                        if trabajando {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Trabajando…") }
                        } else {
                            Text("Crear MKV ahora")
                        }
                    }
                    .disabled(trabajando || leyendo || audiosMarcados.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 880, height: 640)
        .task { await leer() }
    }

    /// Lista desplegable de idiomas preestablecidos. `sinCambios` = la opción de dejar la
    /// pista como viene (nil en los .srt añadidos, que siempre llevan idioma).
    private func selectorDeIdioma(_ seleccion: Binding<Idioma?>, sinCambios: String?) -> some View {
        Picker("", selection: seleccion) {
            if let sinCambios {
                Text(sinCambios).tag(Idioma?.none)
                Divider()
            }
            ForEach(Idioma.lista) { idioma in
                Text(idioma.nombre).tag(Optional(idioma))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .help("Idioma con el que se rotula esta pista en el MKV nuevo")
    }

    private func marca(_ titulo: String, _ activo: Bool, _ cambio: @escaping (Bool) -> Void) -> some View {
        Toggle(titulo, isOn: Binding(get: { activo }, set: cambio))
            .toggleStyle(.checkbox)
            .lineLimit(2).truncationMode(.middle)
            .layoutPriority(1)   // el nombre de la pista manda sobre la lista de idiomas
    }

    private func alternar<T: Hashable>(_ conjunto: inout Set<T>, _ valor: T, _ activo: Bool) {
        if activo { conjunto.insert(valor) } else { conjunto.remove(valor) }
    }

    private func añadirExterno() {
        let panel = NSOpenPanel()
        panel.title = "Elegir el subtítulo"
        panel.prompt = "Añadir"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !externos.contains(url) {
            externos.append(url)
            externosMarcados.insert(url)
        }
    }

    private func leer() async {
        let url = video
        let (encontrados, todas) = await Task.detached {
            ((try? Sondeo.audios(de: url)) ?? [], (try? Sondeo.pistas(de: url)) ?? [])
        }.value
        audios = encontrados
        subtitulos = todas
        if FileManager.default.fileExists(atPath: srtJunto.path) { externos.append(srtJunto) }

        nombreInicial = Remux.destino(para: video).deletingPathExtension().lastPathComponent
        nombre = planActual?.nombre ?? nombreInicial
        if let planActual {
            idiomasAudio = planActual.idiomasDeAudio
            idiomasSubs = planActual.idiomasDeSubtitulo
            idiomasExternos = planActual.idiomasDeAñadidos
            audiosMarcados = Set(planActual.audios)
            subsMarcados = Set(planActual.subtitulosDelArchivo.map(\.indice))
            for añadido in planActual.añadidos where !externos.contains(añadido) { externos.append(añadido) }
            externosMarcados = Set(planActual.añadidos)
        } else {
            // Lo habitual: el inglés (o todo, si no hay) y lo que ya venga en español.
            let ingles = encontrados.filter(\.esIngles)
            audiosMarcados = Set((ingles.isEmpty ? encontrados : ingles).map(\.indice))
            subsMarcados = Set(todas.filter(\.esEspañol).map(\.indice))
        }
        leyendo = false
    }

    /// Extracción manual: deja el .srt junto a la película (lo que antes hacía «Procesar»).
    private func extraer(_ pista: Pista) {
        trabajando = true
        error = nil
        aviso = nil
        let origen = video, destino = srtJunto
        Task {
            let r = await Motor.procesar(origen, opciones: Motor.Opciones(usarRed: false, forzar: true,
                                                                        pistaPreferida: pista.indice,
                                                                        preferirLatino: false))
            if r.fueBien {
                aviso = "Extraje la pista #\(pista.indice) a «\(destino.lastPathComponent)». Ya puedes añadirlo al MKV."
                if !externos.contains(destino) { externos.insert(destino, at: 0) }
            } else if case .falló(let motivo) = r {
                error = motivo
            } else {
                error = "No se pudo extraer esa pista."
            }
            trabajando = false
        }
    }

    private func crear() {
        trabajando = true
        error = nil
        let origen = video, elegido = plan, avance = avance
        avance.empezar()
        Task {
            do {
                let hecho = try await Task.detached(priority: .userInitiated) {
                    try Remux.hacer(video: origen, plan: elegido) { fraccion in
                        Task { @MainActor in avance.fraccion = fraccion }
                    }
                }.value
                resultado = hecho
                alCrear(hecho)
            } catch {
                self.error = error.localizedDescription
            }
            trabajando = false
        }
    }
}

// MARK: - Barra de progreso

/// El avance de la hoja: una clase aparte para que el hilo que trabaja pueda avisar sin tocar la vista.
@MainActor
final class Avance: ObservableObject {
    @Published var fraccion = 0.0
    @Published var mostrar = false
    var inicio: Date?

    func empezar() {
        fraccion = 0
        inicio = Date()
        mostrar = true
    }
}

/// Barra verde con brillo, porcentaje y tiempo restante estimado.
struct BarraVerde: View {
    let fraccion: Double
    var inicio: Date?

    private let claro = Color(red: 0.30, green: 0.85, blue: 0.42)
    private let oscuro = Color(red: 0.10, green: 0.62, blue: 0.27)

    private var restante: String? {
        guard let inicio, fraccion > 0.02, fraccion < 1 else { return nil }
        let segundos = Date().timeIntervalSince(inicio) * (1 - fraccion) / fraccion
        if segundos < 60 { return "faltan ~\(Int(segundos.rounded(.up))) s" }
        return "faltan ~\(Int((segundos / 60).rounded(.up))) min"
    }

    var body: some View {
        let f = min(1, max(0, fraccion))
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { medida in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.12)))
                    Capsule()
                        .fill(LinearGradient(colors: [claro, oscuro], startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .top) {   // el reflejo que le da volumen
                            Capsule()
                                .fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(height: 6)
                                .padding(.horizontal, 3).padding(.top, 1.5)
                        }
                        .frame(width: max(16, medida.size.width * f))
                        .shadow(color: claro.opacity(0.55), radius: 5)
                }
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.45), value: f)

            HStack {
                Text("\(Int((f * 100).rounded())) %")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(oscuro)
                Spacer()
                if let restante {
                    Text(restante).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progreso")
        .accessibilityValue("\(Int((f * 100).rounded())) por ciento")
    }
}

// MARK: - Sello «listo»

/// Un fotograma del sello: se usa en la animación y para dibujar la tira de ejemplo.
struct CuadroDelSello: View {
    var escala: CGFloat = 1
    var opacidad: Double = 1
    var giro: Double = 0
    /// 0 = sin onda; de ahí a 1, la onda verde se abre y se desvanece.
    var onda: Double = 0

    private let verde = Color(red: 0.20, green: 0.78, blue: 0.35)

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(verde, lineWidth: 2.5)
                .scaleEffect(1 + 1.3 * onda)
                .opacity(onda > 0 ? 0.6 * (1 - onda) : 0)
            ZStack {
                Circle()
                    .fill(verde)
                    .shadow(color: verde.opacity(0.5), radius: 5)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .scaleEffect(escala)
            .rotationEffect(.degrees(giro))
            .opacity(opacidad)
        }
        .frame(width: 28, height: 28)
    }
}

/// El check grande que cae como un sello al terminar: aparece ladeado y enorme, rebota
/// hasta su tamaño y suelta una onda verde al impactar. Con «Reducir movimiento» sólo aparece.
struct SelloListo: View {
    var animar = true
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var escala: CGFloat = 1.9
    @State private var opacidad = 0.0
    @State private var giro = -14.0
    @State private var onda = 0.0

    var body: some View {
        CuadroDelSello(escala: escala, opacidad: opacidad, giro: giro, onda: onda)
            .accessibilityLabel("Listo")
            .onAppear(perform: estampar)
    }

    private func estampar() {
        guard animar, !sinMovimiento else {
            escala = 1; opacidad = 1; giro = 0
            return
        }
        // Tiempos pensados para que se alcance a ver: aparece (0,4 s), se queda grande un instante,
        // cae con un rebote lento y al golpear suelta la onda, que tarda más de un segundo en apagarse.
        withAnimation(.easeOut(duration: 0.4)) { opacidad = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.5)) {
                escala = 1
                giro = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {   // el golpe
            onda = 0.001
            withAnimation(.easeOut(duration: 1.3)) { onda = 1 }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }
}
