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
        .onAppear(perform: cargarDesdeArgumentos)
        .overlay(alignment: .bottom) {
            if let mensaje = cola.mensajeDeHerramientas {
                AvisoDeHerramientas(mensaje: mensaje)
            }
        }
    }

    /// `open -a SubFix --env SUBFIX_CARGAR="/ruta/uno:/ruta/dos"` arranca con eso ya en la lista.
    /// (Rutas como argumentos no sirven: macOS las toma por documentos y no abre la ventana.)
    private func cargarDesdeArgumentos() {
        guard let lista = ProcessInfo.processInfo.environment["SUBFIX_CARGAR"] else { return }
        let rutas = lista.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        if !rutas.isEmpty { cola.agregar(rutas) }
        // Con SUBFIX_SUBDIVX=1 además abre la ventana de Subdivx con todo lo cargado (para revisarla).
        if ProcessInfo.processInfo.environment["SUBFIX_SUBDIVX"] == "1" {
            Task {
                try? await Task.sleep(for: .seconds(2))
                cola.abrirSubdivxCon = cola.filas.map(\.id)
            }
        }
    }
}

// MARK: - Películas

struct VistaPeliculas: View {
    @ObservedObject var cola: Cola
    @State private var encima = false
    @State private var paraMKV: Fila?
    @State private var paraSubdivx: LoteSubdivx?
    @State private var filtro = Filtro.todas

    enum Filtro: String, CaseIterable, Identifiable {
        case todas = "Todas"
        case porRevisar = "Por revisar"
        case listas = "Listas"
        var id: Self { self }
    }

    /// Los capítulos se agrupan por serie y temporada; las películas, aparte.
    private var grupos: [(titulo: String, filas: [Fila])] {
        let visibles = cola.filas.filter { fila in
            switch filtro {
            case .todas: return true
            case .porRevisar: return fila.porRevisar
            case .listas: return fila.terminada
            }
        }
        var orden: [String] = []
        var porGrupo: [String: [Fila]] = [:]
        for fila in visibles {
            let grupo = fila.visible.grupo
            if porGrupo[grupo] == nil { orden.append(grupo) }
            porGrupo[grupo, default: []].append(fila)
        }
        return orden.map { grupo in
            (grupo, porGrupo[grupo]!.sorted { $0.visible.orden < $1.visible.orden })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if cola.filas.isEmpty {
                ZonaVacia(encima: encima, explorar: explorar)
            } else {
                encabezado
                Divider()
                lista
            }

            if let aviso = cola.aviso {
                Franja(texto: aviso, icono: "exclamationmark.triangle.fill", color: .orange) { cola.aviso = nil }
            } else if let nota = cola.nota {
                Franja(texto: nota, icono: "checkmark.circle.fill", color: .green) { cola.nota = nil }
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
        .sheet(item: $paraSubdivx) { lote in
            HojaDeSubdivx(lote: lote) { archivo, id in
                if let id { return cola.adoptarDescarga(archivo, para: id) }
                return cola.adoptarDescarga(archivo, entre: lote.trabajos.map(\.id))
            }
        }
        // Al terminar de procesar, la cola pide Subdivx para los que quedaron sin latino.
        .onChange(of: cola.abrirSubdivxCon) { _, ids in
            guard let ids, paraSubdivx == nil, paraMKV == nil else { return }
            buscarEnSubdivx(cola.filas.filter { ids.contains($0.id) })
            cola.abrirSubdivxCon = nil
        }
    }

    // MARK: Encabezado: resumen, filtro y opciones

    private var encabezado: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(resumen).font(.headline)
                Text(resumenDeOpciones).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Mostrar", selection: $filtro) {
                ForEach(Filtro.allCases) { f in
                    Text(f == .porRevisar && cuantas(\.porRevisar) > 0
                         ? "\(f.rawValue) (\(cuantas(\.porRevisar)))" : f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            menuDeOpciones
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func cuantas(_ condicion: KeyPath<Fila, Bool>) -> Int {
        cola.filas.filter { $0[keyPath: condicion] }.count
    }

    private var resumen: String {
        let capitulos = cola.filas.filter(\.esEpisodio).count
        let peliculas = cola.filas.count - capitulos
        let cosas = [capitulos > 0 ? (capitulos == 1 ? "1 capítulo" : "\(capitulos) capítulos") : nil,
                     peliculas > 0 ? (peliculas == 1 ? "1 película" : "\(peliculas) películas") : nil]
        var partes = [cosas.compactMap { $0 }.joined(separator: " y ")]
        let listas = cuantas(\.terminada), revisar = cuantas(\.porRevisar), pendientes = cola.pendientes.count
        if listas > 0 { partes.append("\(listas) list\(listas == 1 ? "o" : "os")") }
        if revisar > 0 { partes.append("\(revisar) por revisar") }
        if pendientes > 0 { partes.append("\(pendientes) pendiente\(pendientes == 1 ? "" : "s")") }
        return partes.joined(separator: " · ")
    }

    /// Lo que va a hacer «Procesar», dicho en una línea.
    private var resumenDeOpciones: String {
        var partes: [String] = []
        switch (cola.usarRed, cola.extraerDelArchivo) {
        case (true, false): partes.append("Busca en internet")
        case (true, true): partes.append("Busca en internet y extrae del archivo")
        case (false, true): partes.append("Sólo extrae del archivo")
        case (false, false): partes.append("⚠️ No busca en internet ni extrae: Procesar no hará nada")
        }
        if cola.preferirLatino { partes.append("sólo latino (España, si tú lo apruebas)") }
        if cola.subdivxAlTerminar { partes.append("lo que falte, a Subdivx") }
        if cola.organizar { partes.append("cada capítulo a su carpeta") }
        return partes.joined(separator: " · ")
    }

    private var menuDeOpciones: some View {
        Menu {
            Section("Al procesar") {
                Toggle("Buscar en internet (Addic7ed y OpenSubtitles)", isOn: $cola.usarRed)
                Toggle("Extraer también la pista del archivo", isOn: $cola.extraerDelArchivo)
                Toggle("Pedir latino: el de España sólo si lo apruebo", isOn: $cola.preferirLatino)
            }
            Section("Al terminar") {
                Toggle("Buscar en Subdivx los que queden sin latino", isOn: $cola.subdivxAlTerminar)
                Toggle("Meter cada capítulo en su carpeta", isOn: $cola.organizar)
            }
        } label: {
            Label("Opciones", systemImage: "slider.horizontal.3")
        }
        .fixedSize()
        .help("Qué hace «Procesar». Se recuerda para la próxima vez")
    }

    // MARK: Lista

    private var lista: some View {
        List {
            ForEach(grupos, id: \.titulo) { grupo in
                Section {
                    ForEach(grupo.filas) { fila in
                        FilaDePelicula(fila: fila,
                                       preferirLatino: cola.preferirLatino && cola.usarRed,
                                       extraerDelArchivo: cola.extraerDelArchivo,
                                       acciones: acciones(para: fila))
                            .contextMenu { MenuDeFila(fila: fila, acciones: acciones(para: fila)) }
                    }
                } header: {
                    if grupos.count > 1 || grupo.titulo != "Películas" {
                        Text(grupo.titulo)
                    }
                }
            }
            if grupos.isEmpty {
                Text(filtro == .porRevisar ? "Nada por revisar." : "Todavía no hay nada listo.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            }
        }
        .listStyle(.inset)
    }

    private func acciones(para fila: Fila) -> AccionesDeFila {
        AccionesDeFila(
            elegirPista: { cola.elegirPista(fila.id, indice: $0) },
            abrirPistas: { paraMKV = fila },
            abrirSubdivx: { buscarEnSubdivx([fila]) },
            usarEspaña: { cola.usarEspaña(fila.id) },
            reintentar: { cola.reintentar(fila.id) },
            quitar: { cola.quitar(fila.id) })
    }

    private func buscarEnSubdivx(_ filas: [Fila]) {
        guard !filas.isEmpty else { return }
        paraSubdivx = LoteSubdivx(trabajos: filas.map(TrabajoSubdivx.init))
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

    // MARK: Barra inferior

    private var barraInferior: some View {
        HStack(spacing: 10) {
            Button(action: explorar) {
                Label("Añadir…", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(cola.trabajando)
            .help("Elegir películas, carpetas o el .zip/.srt de Subdivx (⌘O). También puedes arrastrarlos")

            if cola.filas.contains(where: \.esEpisodio) {
                Button {
                    cola.organizarTodos()
                } label: {
                    Label("Organizar en carpetas", systemImage: "folder.badge.plus")
                }
                .disabled(cola.trabajando || !cola.hayCapitulosPorOrganizar)
                .help(cola.hayCapitulosPorOrganizar
                      ? "Mete cada capítulo (video, .srt y MKV) en su carpeta, p. ej. «Ted Lasso S03E01». Nunca pisa nada"
                      : "Todos los capítulos ya están en su carpeta")
            }

            if !cola.filas.isEmpty {
                Button {
                    cola.extraerLatinoEnTodos()
                } label: {
                    Label("Extraer latino", systemImage: "text.bubble")
                }
                .disabled(cola.trabajando || cola.paraLatinoPorDefecto.isEmpty)
                .help("En toda la lista: saca del archivo el subtítulo latino, lo limpia de publicidad y caracteres "
                      + "raros, lo deja como .srt al lado (el que el TV pone solo) y mete cada capítulo en su carpeta. Sin internet")

                Button {
                    cola.latinoPorDefectoEnTodos()
                } label: {
                    Label("Latino por defecto", systemImage: "globe.americas")
                }
                .disabled(cola.trabajando || cola.paraLatinoPorDefecto.isEmpty)
                .help("Sólo eso: en cada MKV de la lista deja automático el subtítulo latino y, si lo trae, "
                      + "el audio latino. Cambia el mismo archivo (sólo la cabecera, en un segundo); no crea otro")
            }

            if !cola.faltanEnSubdivx.isEmpty {
                Button {
                    buscarEnSubdivx(cola.faltanEnSubdivx)
                } label: {
                    Label("Subdivx (\(cola.faltanEnSubdivx.count))", systemImage: "magnifyingglass")
                }
                .disabled(cola.trabajando)
                .help("Abre Subdivx y baja, uno por uno, el latino de los que quedaron en naranja")
            }

            Spacer()

            if !cola.filas.isEmpty {
                Button("Vaciar lista") { cola.vaciar() }
                    .disabled(cola.trabajando)
                    .help("Quita todo de la lista. No toca ningún archivo")
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
                    Text(cola.pendientes.isEmpty ? "Procesar" : "Procesar \(cola.pendientes.count)")
                        .frame(minWidth: 80)
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(cola.pendientes.isEmpty || cola.trabajando)
        }
        .padding(12)
    }
}

/// Franja de aviso (naranja) o de nota (verde) sobre la barra inferior.
struct Franja: View {
    let texto: String
    let icono: String
    let color: Color
    let cerrar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icono).foregroundStyle(color)
            Text(texto).font(.callout).lineLimit(3)
            Spacer()
            Button("Cerrar", action: cerrar).buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.08))
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
            Text("Arrastra películas, capítulos o una carpeta")
                .font(.title3)
            Text("SubFix busca el subtítulo en español latino y lo deja listo para el Samsung:\n"
                 + "mismo nombre que el video, UTF-8 con BOM y CRLF.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Añadir…", action: explorar)
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

/// Lo que se puede hacer con una fila, para la propia fila, su menú «⋯» y el clic derecho.
public struct AccionesDeFila {
    var elegirPista: (Int) -> Void = { _ in }
    var abrirPistas: () -> Void = {}
    var abrirSubdivx: () -> Void = {}
    var usarEspaña: () -> Void = {}
    var reintentar: () -> Void = {}
    var quitar: () -> Void = {}

    static let ninguna = AccionesDeFila()
}

struct FilaDePelicula: View {
    let fila: Fila
    let preferirLatino: Bool
    let extraerDelArchivo: Bool
    let acciones: AccionesDeFila

    private var detalle: String {
        fila.estado.detalle ?? fila.plan?.resumen
            ?? fila.diagnostico?.plan(preferirLatino: preferirLatino, extraerDelArchivo: extraerDelArchivo,
                                     pistaManual: fila.pistaElegida != nil) ?? ""
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: fila.estado.icono)
                .foregroundStyle(fila.estado.color)
                .font(.title3)
                .frame(width: 22)
                .symbolEffect(.pulse, isActive: fila.estado == .procesando)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if let codigo = fila.visible.codigo {
                        Text(codigo)
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(fila.visible.titulo.isEmpty ? fila.nombre : fila.visible.titulo)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if fila.terminada { SelloListo().id(fila.id) }
                }
                .help(fila.url.path)

                Text(detalle)
                    .font(.callout)
                    .foregroundStyle(fila.porRevisar ? AnyShapeStyle(fila.estado.color) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .help(detalle)

                if fila.estado == .procesando, let avance = fila.progreso {
                    BarraVerde(fraccion: avance, inicio: fila.inicioDeProgreso)
                        .frame(maxWidth: 420)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            botonesPrincipales

            if fila.estado != .procesando, fila.estado != .analizando {
                Menu {
                    MenuDeFila(fila: fila, acciones: acciones)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Más acciones")
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 54)   // sitio para que el sello llegue grande sin que la fila lo recorte
    }

    /// Como mucho dos botones a la vista: lo que toca hacer ahora con esta fila.
    @ViewBuilder private var botonesPrincipales: some View {
        switch fila.estado {
        case .avisada:
            if fila.candidatoEspaña != nil {
                Button("Usar el de España", action: acciones.usarEspaña)
                    .help("Sólo apareció en español de España. Todavía no está puesto: con este botón lo dejas junto al video")
            }
            Button(action: acciones.abrirSubdivx) {
                Label("Subdivx", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .help("Abre Subdivx dentro de SubFix, busca «\(TrabajoSubdivx(fila: fila).busqueda)» y baja solo el latino. "
                  + "Si sale «Verifica que eres humano», márcalo tú")
        case .fallada:
            Button(action: acciones.reintentar) {
                Label("Reintentar", systemImage: "arrow.clockwise")
            }
            .help("Vuelve a dejarla pendiente para el próximo «Procesar»")
        case .hecha:
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([fila.archivoParaMostrar])
            } label: {
                Label("Mostrar", systemImage: "folder")
            }
            .help("Mostrar «\(fila.archivoParaMostrar.lastPathComponent)» en el Finder")
        case .listaParaProcesar where fila.plan != nil:
            Button(action: acciones.abrirPistas) {
                Label("Pistas ✓", systemImage: "slider.horizontal.3")
            }
            .help("Ya armaste el MKV de esta fila: «Procesar» lo crea. Toca para cambiarlo")
        default:
            EmptyView()
        }
    }
}

/// Todas las acciones de una fila; lo usan el botón «⋯» y el clic derecho.
struct MenuDeFila: View {
    let fila: Fila
    let acciones: AccionesDeFila

    var body: some View {
        if !fila.terminada, fila.estado != .procesando {
            Button(fila.plan == nil ? "Pistas del MKV…" : "Cambiar las pistas del MKV…", action: acciones.abrirPistas)
        }
        if let diagnostico = fila.diagnostico, diagnostico.pistas.filter(\.esTexto).count > 1,
           fila.estado == .listaParaProcesar {
            Menu("Extraer esta pista") {
                ForEach(diagnostico.pistas.filter(\.esTexto)) { pista in
                    Button {
                        acciones.elegirPista(pista.indice)
                    } label: {
                        let elegida = fila.pistaElegida == pista.indice
                        Label(pista.resumen, systemImage: elegida ? "checkmark" : "")
                    }
                }
            }
        }
        Button("Buscar en Subdivx…", action: acciones.abrirSubdivx)
        if fila.candidatoEspaña != nil {
            Button("Usar el de España", action: acciones.usarEspaña)
        }
        if fila.porRevisar {
            Button("Volver a procesar", action: acciones.reintentar)
        }
        Divider()
        Button("Mostrar en el Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([fila.archivoParaMostrar])
        }
        Button("Quitar de la lista", action: acciones.quitar)
    }
}

extension Fila {
    /// El MKV recién creado; si no hubo, el .srt que quedó junto al video; si tampoco, el video.
    var archivoParaMostrar: URL {
        if let listo = archivoListo, FileManager.default.fileExists(atPath: listo.path) { return listo }
        let srt = Motor.destinoSRT(de: url)
        return FileManager.default.fileExists(atPath: srt.path) ? srt : url
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
