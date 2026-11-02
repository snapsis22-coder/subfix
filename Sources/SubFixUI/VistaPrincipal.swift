import AppKit
import SubFixKit
import SwiftUI
import UniformTypeIdentifiers

/// Las tres secciones de la app, como pestañas dentro de la cabecera morada.
enum Pestaña: String, CaseIterable, Identifiable {
    case subtitulos = "Subtítulos"
    case organizar = "Organizar"
    case vigilancia = "Vigilar"

    var id: Self { self }

    var icono: String {
        switch self {
        case .subtitulos: return "captions.bubble.fill"
        case .organizar: return "wand.and.stars"
        case .vigilancia: return "eye.fill"
        }
    }

    var lema: String {
        switch self {
        case .subtitulos: return "Deja los subtítulos listos para el televisor"
        case .organizar: return "Ordena tus películas y series para Jellyfin y Plex"
        case .vigilancia: return "Procesa sola cada película nueva de una carpeta"
        }
    }
}

public struct VistaPrincipal: View {
    @StateObject private var cola = Cola()
    @StateObject private var vigilante = Vigilante()
    @StateObject private var organizador = Organizador()
    @AppStorage("subfix.pestaña") private var pestaña = Pestaña.subtitulos
    @State private var entradaRevisada = false

    public init() {}

    public var body: some View {
        Ventana(pestaña: $pestaña, cola: cola, vigilante: vigilante, organizador: organizador)
            .onAppear {
                cargarDesdeArgumentos()
                revisarEntradaSiToca(pestaña)
            }
            .onChange(of: pestaña) { _, nueva in revisarEntradaSiToca(nueva) }
            .onChange(of: organizador.entrada) { _, _ in revisarEntradaSiToca(pestaña) }
            // Al volver a la app (p. ej. tras terminar una descarga) se mira otra vez.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if pestaña == .subtitulos { cola.revisarDescargas(organizador.entrada) }
            }
    }

    /// La carpeta de descargas se mira la primera vez que se abre «Organizar», no al arrancar.
    /// «Subtítulos» mira la misma carpeta cada vez que se abre: sólo agrega lo nuevo.
    private func revisarEntradaSiToca(_ p: Pestaña) {
        if p == .subtitulos { cola.revisarDescargas(organizador.entrada) }
        guard p == .organizar, !entradaRevisada else { return }
        entradaRevisada = true
        organizador.revisarEntrada()
    }

    /// `open -a SubFix --env SUBFIX_CARGAR="/ruta/uno:/ruta/dos"` arranca con eso ya en la lista.
    /// (Rutas como argumentos no sirven: macOS las toma por documentos y no abre la ventana.)
    private func cargarDesdeArgumentos() {
        guard let lista = ProcessInfo.processInfo.environment["SUBFIX_CARGAR"] else { return }
        let rutas = lista.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        if !rutas.isEmpty {
            pestaña = .subtitulos
            cola.agregar(rutas)
        }
        // Con SUBFIX_SUBDIVX=1 además abre la ventana de Subdivx con todo lo cargado (para revisarla).
        if ProcessInfo.processInfo.environment["SUBFIX_SUBDIVX"] == "1" {
            Task {
                try? await Task.sleep(for: .seconds(2))
                cola.abrirSubdivxCon = cola.filas.map(\.id)
            }
        }
    }
}

/// La ventana entera, separada de `VistaPrincipal` para poder retratarla con datos de muestra.
struct Ventana: View {
    @Binding var pestaña: Pestaña
    @ObservedObject var cola: Cola
    @ObservedObject var vigilante: Vigilante
    @ObservedObject var organizador: Organizador
    /// ScrollView es AppKit y sale en blanco en los retratos: ahí se pintan las listas sin él.
    var sinScroll = false

    var body: some View {
        VStack(spacing: 0) {
            CabeceraSubFix(pestaña: $pestaña) { accesorio }
            Group {
                switch pestaña {
                case .subtitulos: VistaPeliculas(cola: cola, entradaDeOrganizar: organizador.entrada, sinScroll: sinScroll)
                case .organizar: VistaOrganizar(modelo: organizador, sinScroll: sinScroll)
                case .vigilancia: VistaVigilancia(vigilante: vigilante, sinScroll: sinScroll)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Tema.fondo)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) {
            if let mensaje = cola.mensajeDeHerramientas {
                AvisoDeHerramientas(mensaje: mensaje)
            }
        }
    }

    /// Lo que va a la derecha de la cabecera según la pestaña.
    @ViewBuilder private var accesorio: some View {
        switch pestaña {
        case .subtitulos:
            EmptyView()
        case .organizar:
            InterruptorAutomatico(encendido: $organizador.automatico)
        case .vigilancia:
            InterruptorAutomatico(encendido: $vigilante.activo, titulo: "Vigilar",
                                  textoEncendido: "Revisa cada 30 segundos", icono: "eye",
                                  ayuda: vigilante.carpeta == nil
                                      ? "Primero elige la carpeta que quieres vigilar"
                                      : "Procesa sola cada película que termine de bajar en la carpeta, mientras la app esté abierta",
                                  activo: vigilante.carpeta != nil)
        }
    }
}

// MARK: - Cabecera

struct CabeceraSubFix<Accesorio: View>: View {
    @Binding var pestaña: Pestaña
    @ViewBuilder var accesorio: Accesorio

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18))
                    Image(systemName: "captions.bubble.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SubFix")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(pestaña.lema)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .contentTransition(.opacity)
                }
                Spacer()
                accesorio
            }

            HStack(spacing: 8) {
                ForEach(Array(Pestaña.allCases.enumerated()), id: \.element) { i, p in
                    BotonDePestaña(pestaña: p, elegida: p == pestaña) {
                        withAnimation(.easeOut(duration: 0.15)) { pestaña = p }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 38)                  // aire para los semáforos de la ventana
        .padding(.bottom, 16)
        .background(
            ZStack {
                Tema.degradado
                // Dos luces suaves para que el degradado no se vea plano.
                Circle().fill(.white.opacity(0.10)).frame(width: 260).offset(x: 320, y: -70).blur(radius: 2)
                Circle().fill(Color(suave: 1.0, green: 0.85, blue: 0.40).opacity(0.30)).frame(width: 220).offset(x: -380, y: 50).blur(radius: 34)
            }
            .clipped()
        )
    }
}

/// Una pestaña de la cabecera: blanca con texto morado la elegida, translúcida las demás.
struct BotonDePestaña: View {
    let pestaña: Pestaña
    let elegida: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Label(pestaña.rawValue, systemImage: pestaña.icono)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(elegida ? Tema.morado : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(elegida ? Color.white : .white.opacity(encima ? 0.24 : 0.13)))
                .overlay(Capsule().strokeBorder(.white.opacity(elegida ? 0 : 0.22), lineWidth: 1))
                .shadow(color: .black.opacity(elegida ? 0.14 : 0), radius: 6, y: 2)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .animation(.easeOut(duration: 0.15), value: encima)
        .help("\(pestaña.rawValue): \(pestaña.lema.lowercased())")
    }
}

// MARK: - Piezas compartidas

/// Control segmentado propio: el del sistema sale gris y no combina con el morado.
struct Segmentos<Valor: Hashable>: View {
    let opciones: [(valor: Valor, texto: String)]
    @Binding var seleccion: Valor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(opciones, id: \.valor) { opcion in
                let elegida = opcion.valor == seleccion
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { seleccion = opcion.valor }
                } label: {
                    Text(opcion.texto)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(elegida ? .white : Tema.tintaSuave)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(elegida ? AnyShapeStyle(Tema.degradadoBoton) : AnyShapeStyle(Color.clear)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Tema.tarjeta))
        .overlay(Capsule().strokeBorder(Tema.borde, lineWidth: 1))
        .fixedSize()
    }
}

/// El cuadrito de color de cada fila: morado-rosa para películas, azul para series.
struct IconoDeTipo: View {
    let esSerie: Bool
    var simbolo: String?
    var latiendo = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(esSerie ? Tema.degradadoSerie : Tema.degradadoPelicula)
            Image(systemName: simbolo ?? (esSerie ? "tv" : "film"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, isActive: latiendo)
        }
        .frame(width: 42, height: 42)
        .shadow(color: (esSerie ? Tema.indigo : Tema.morado).opacity(0.3), radius: 6, y: 3)
    }
}

/// Fondo de tarjeta blanca (berenjena de noche) con borde suave que se tiñe al pasar el ratón.
struct FondoDeTarjeta: ViewModifier {
    var radio: CGFloat = 16
    @State private var encima = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radio).fill(Tema.tarjeta))
            .overlay(RoundedRectangle(cornerRadius: radio)
                .strokeBorder(encima ? Tema.morado.opacity(0.35) : Tema.borde, lineWidth: 1))
            .shadow(color: Tema.morado.opacity(encima ? 0.12 : 0.05), radius: encima ? 10 : 5, y: 3)
            .onHover { encima = $0 }
            .animation(.easeOut(duration: 0.15), value: encima)
    }
}

extension View {
    func tarjeta(radio: CGFloat = 16) -> some View { modifier(FondoDeTarjeta(radio: radio)) }
}

/// La barra de abajo de cada sección: blanca, con una línea fina encima.
struct FondoDeBarra: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Tema.tarjeta)
            .overlay(alignment: .top) { Rectangle().fill(Tema.borde).frame(height: 1) }
    }
}

/// Encabezado de grupo en las listas: «TED LASSO · TEMPORADA 3  12».
struct TituloDeGrupo: View {
    let titulo: String
    let cuantos: Int
    let esSerie: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: esSerie ? "tv" : "film").font(.system(size: 10, weight: .bold))
            Text(titulo.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.8)
            Text("\(cuantos)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Tema.morado.opacity(0.10)))
        }
        .foregroundStyle(esSerie ? Tema.acentoSerie : Tema.acento)
        .padding(.leading, 4)
    }
}

// MARK: - Subtítulos

struct VistaPeliculas: View {
    @ObservedObject var cola: Cola
    /// La entrada de «Organizar»: la que se revisa si no se eligió otra aquí.
    var entradaDeOrganizar: URL? = nil
    var sinScroll = false
    @State private var encima = false
    @State private var paraMKV: Fila?
    @State private var paraSubdivx: LoteSubdivx?
    @State private var filtro = Filtro.todas
    @State private var viendoOpciones = false

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
                if sinScroll {
                    lista.frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView { lista }
                }
            }

            if let aviso = cola.aviso {
                Franja(texto: aviso, icono: "exclamationmark.triangle.fill", color: Tema.ambar) { cola.aviso = nil }
            } else if let nota = cola.nota {
                Franja(texto: nota, icono: "checkmark.circle.fill", color: Tema.verde) { cola.nota = nil }
            }
            barraInferior
        }
        .onDrop(of: [.fileURL], isTargeted: $encima) { proveedores in
            recibir(proveedores)
            return true
        }
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
            VStack(alignment: .leading, spacing: 3) {
                Text(resumen)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.tinta)
                Text(resumenDeOpciones)
                    .font(.system(size: 11.5))
                    .foregroundStyle(cola.usarRed || cola.extraerDelArchivo ? Tema.tintaSuave : Tema.ambar)
                    .lineLimit(2)
            }

            Spacer()

            Segmentos(opciones: Filtro.allCases.map { f in
                (f, f == .porRevisar && cuantas(\.porRevisar) > 0 ? "\(f.rawValue) (\(cuantas(\.porRevisar)))" : f.rawValue)
            }, seleccion: $filtro)

            Button { viendoOpciones.toggle() } label: {
                Label("Opciones", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(BotonSecundario(compacto: true))
            .help("Qué hace «Procesar». Se recuerda para la próxima vez")
            .popover(isPresented: $viendoOpciones, arrowEdge: .bottom) {
                PanelDeOpciones(cola: cola)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 4)
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

    // MARK: Lista

    private var lista: some View {
        // VStack y no LazyVStack: así también sale en los retratos.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(grupos, id: \.titulo) { grupo in
                if grupos.count > 1 || grupo.titulo != "Películas" {
                    TituloDeGrupo(titulo: grupo.titulo, cuantos: grupo.filas.count,
                                  esSerie: grupo.filas.first?.esEpisodio ?? false)
                        .padding(.top, 10)
                }
                ForEach(grupo.filas) { fila in
                    FilaDePelicula(fila: fila,
                                   preferirLatino: cola.preferirLatino && cola.usarRed,
                                   extraerDelArchivo: cola.extraerDelArchivo,
                                   acciones: acciones(para: fila))
                        .contextMenu { MenuDeFila(fila: fila, acciones: acciones(para: fila)) }
                }
            }
            if grupos.isEmpty {
                Text(filtro == .porRevisar ? "Nada por revisar." : "Todavía no hay nada listo.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.tintaSuave)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 18)
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

    /// Lo soltado en la ventana, todo junto para que la cola lo reciba de una vez.
    private func recibir(_ proveedores: [NSItemProvider]) {
        Task { @MainActor in
            var rutas: [URL] = []
            for proveedor in proveedores {
                let url = await withCheckedContinuation { (seguir: CheckedContinuation<URL?, Never>) in
                    _ = proveedor.loadObject(ofClass: URL.self) { url, _ in seguir.resume(returning: url) }
                }
                if let url { rutas.append(url) }
            }
            if !rutas.isEmpty { cola.agregar(rutas) }
        }
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

    /// La carpeta que se revisa sola. Clic: cambiarla. Clic derecho: revisar ya o volver a la de Organizar.
    private var botonDeCarpeta: some View {
        let carpeta = cola.carpetaPropia ?? entradaDeOrganizar
        let ruta = carpeta?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return Button {
            cola.elegirCarpetaDeDescargas(porDefecto: entradaDeOrganizar)
        } label: {
            Label(carpeta?.lastPathComponent ?? "Elegir carpeta…", systemImage: "tray.and.arrow.down.fill")
                .lineLimit(1)
        }
        .buttonStyle(BotonSecundario(compacto: true))
        .disabled(cola.trabajando)
        .help(ruta.map { "Reviso sola «\($0)» cada vez que vuelves aquí y traigo los videos nuevos. "
                         + "Clic para cambiarla; clic derecho para más" }
              ?? "Elige qué carpeta reviso sola para traer los videos nuevos")
        .contextMenu {
            Button("Revisar ahora") { cola.revisarDescargas(entradaDeOrganizar) }
                .disabled(carpeta == nil)
            Button("Cambiar carpeta…") { cola.elegirCarpetaDeDescargas(porDefecto: entradaDeOrganizar) }
            Divider()
            Button("Usar la misma de Organizar") { cola.usarLaDeOrganizar(entradaDeOrganizar) }
                .disabled(cola.carpetaPropia == nil || entradaDeOrganizar == nil)
        }
    }

    private var barraInferior: some View {
        HStack(spacing: 8) {
            botonDeCarpeta

            Button(action: explorar) {
                Label("Añadir…", systemImage: "plus")
            }
            .buttonStyle(BotonSecundario(compacto: true))
            .keyboardShortcut("o", modifiers: .command)
            .disabled(cola.trabajando)
            .help("Elegir películas, carpetas o el .zip/.srt de Subdivx (⌘O). También puedes arrastrarlos")

            if cola.filas.contains(where: \.esEpisodio) {
                Button {
                    cola.organizarTodos()
                } label: {
                    Label("Organizar en carpetas", systemImage: "folder.badge.plus")
                }
                .buttonStyle(BotonSecundario(compacto: true))
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
                .buttonStyle(BotonSecundario(compacto: true))
                .disabled(cola.trabajando || cola.paraLatinoPorDefecto.isEmpty)
                .help("En toda la lista: saca del archivo el subtítulo latino, lo limpia de publicidad y caracteres "
                      + "raros, lo deja como .srt al lado (el que el TV pone solo) y mete cada capítulo en su carpeta. Sin internet")

                Button {
                    cola.latinoPorDefectoEnTodos()
                } label: {
                    Label("Latino por defecto", systemImage: "globe.americas")
                }
                .buttonStyle(BotonSecundario(compacto: true))
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
                .buttonStyle(BotonPrincipal(compacto: true, relleno: Tema.degradadoAviso, sombra: Tema.ambar))
                .disabled(cola.trabajando)
                .help("Abre Subdivx y baja, uno por uno, el latino de los que quedaron en naranja")
            }

            Spacer(minLength: 8)

            if !cola.filas.isEmpty {
                Button("Vaciar lista") { cola.vaciar() }
                    .buttonStyle(BotonSecundario(compacto: true))
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
                    Label(cola.pendientes.isEmpty ? "Procesar" : "Procesar \(cola.pendientes.count)",
                          systemImage: "sparkles")
                }
            }
            .buttonStyle(BotonPrincipal())
            .keyboardShortcut(.defaultAction)
            .disabled(cola.pendientes.isEmpty || cola.trabajando)
        }
        .modifier(FondoDeBarra())
    }
}

/// Lo que hace «Procesar», en un globo que sale del botón «Opciones».
struct PanelDeOpciones: View {
    @ObservedObject var cola: Cola

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            seccion("Al procesar") {
                interruptor("Buscar en internet (Addic7ed y OpenSubtitles)", $cola.usarRed)
                interruptor("Extraer también la pista del archivo", $cola.extraerDelArchivo)
                interruptor("Pedir latino: el de España sólo si lo apruebo", $cola.preferirLatino)
            }
            seccion("Al terminar") {
                interruptor("Buscar en Subdivx los que queden sin latino", $cola.subdivxAlTerminar)
                interruptor("Meter cada capítulo en su carpeta", $cola.organizar)
            }
            Text("Se recuerda para la próxima vez.")
                .font(.system(size: 11))
                .foregroundStyle(Tema.tintaSuave)
        }
        .padding(18)
        .frame(width: 400)
        .background(Tema.tarjeta)
    }

    private func seccion<C: View>(_ titulo: String, @ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Tema.acento)
            contenido()
        }
    }

    private func interruptor(_ texto: String, _ valor: Binding<Bool>) -> some View {
        Toggle(isOn: valor) {
            Text(texto).font(.system(size: 13)).foregroundStyle(Tema.tinta)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(Tema.morado)
    }
}

/// Franja de aviso (ámbar) o de nota (verde) sobre la barra inferior.
struct Franja: View {
    let texto: String
    let icono: String
    let color: Color
    let cerrar: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icono).foregroundStyle(color)
            Text(texto)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Tema.tinta)
                .lineLimit(3)
            Spacer()
            Button("Cerrar", action: cerrar).buttonStyle(BotonSecundario(compacto: true))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.30), lineWidth: 1))
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }
}

struct ZonaVacia: View {
    let encima: Bool
    let explorar: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Tema.morado.opacity(0.10)).frame(width: 110, height: 110)
                Circle().fill(Tema.morado.opacity(0.08)).frame(width: 150, height: 150)
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Tema.degradado)
            }
            VStack(spacing: 6) {
                Text("Arrastra películas, capítulos o una carpeta")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.tinta)
                Text("SubFix busca el subtítulo en español latino y lo deja listo para el Samsung: "
                     + "mismo nombre que el video, UTF-8 con BOM y CRLF.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.tintaSuave)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Button(action: explorar) {
                Label("Añadir…", systemImage: "plus")
            }
            .buttonStyle(BotonPrincipal())
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(encima ? AnyShapeStyle(Tema.degradado) : AnyShapeStyle(Tema.borde),
                              style: StrokeStyle(lineWidth: encima ? 3 : 2, dash: [10, 6]))
                .background(RoundedRectangle(cornerRadius: 18).fill(Tema.morado.opacity(encima ? 0.06 : 0)))
                .padding(20)
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
        HStack(alignment: .center, spacing: 14) {
            IconoDeTipo(esSerie: fila.esEpisodio, latiendo: fila.estado == .procesando)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let codigo = fila.visible.codigo {
                        Chip(texto: codigo, color: Tema.acentoSerie)
                    }
                    Text(fila.visible.titulo.isEmpty ? fila.nombre : fila.visible.titulo)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tema.tinta)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if fila.terminada { SelloListo().id(fila.id) }
                }
                .help(fila.url.path)

                if !detalle.isEmpty {
                    Text(detalle)
                        .font(.system(size: 12))
                        .foregroundStyle(fila.porRevisar ? fila.estado.color : Tema.tintaSuave)
                        .lineLimit(2)
                        .help(detalle)
                }

                if fila.estado == .procesando, let avance = fila.progreso {
                    BarraVerde(fraccion: avance, inicio: fila.inicioDeProgreso)
                        .frame(maxWidth: 420)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            if let etiqueta { etiqueta }

            botonesPrincipales

            if fila.estado != .procesando, fila.estado != .analizando {
                Menu {
                    MenuDeFila(fila: fila, acciones: acciones)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(Tema.acento)
                .fixedSize()
                .help("Más acciones")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 66)   // sitio para que el sello llegue grande sin que la fila lo recorte
        .tarjeta()
    }

    /// La cápsula de estado, sólo cuando no hay un botón que ya lo diga.
    private var etiqueta: EtiquetaSimple? {
        switch fila.estado {
        case .analizando: return EtiquetaSimple(texto: "Leyendo…", icono: nil, color: Tema.tintaSuave)
        case .procesando: return EtiquetaSimple(texto: "Procesando…", icono: nil, color: Tema.acento)
        case .listaParaProcesar where fila.plan == nil:
            return EtiquetaSimple(texto: "Pendiente", icono: "circle.dashed", color: Tema.acento)
        default: return nil
        }
    }

    /// Como mucho dos botones a la vista: lo que toca hacer ahora con esta fila.
    @ViewBuilder private var botonesPrincipales: some View {
        switch fila.estado {
        case .avisada:
            if fila.candidatoEspaña != nil {
                Button("Usar el de España", action: acciones.usarEspaña)
                    .buttonStyle(BotonSecundario(compacto: true))
                    .help("Sólo apareció en español de España. Todavía no está puesto: con este botón lo dejas junto al video")
            }
            Button(action: acciones.abrirSubdivx) {
                Label("Subdivx", systemImage: "magnifyingglass")
            }
            .buttonStyle(BotonPrincipal(compacto: true, relleno: Tema.degradadoAviso, sombra: Tema.ambar))
            .help("Abre Subdivx dentro de SubFix, busca «\(TrabajoSubdivx(fila: fila).busqueda)» y baja solo el latino. "
                  + "Si sale «Verifica que eres humano», márcalo tú")
        case .fallada:
            Button(action: acciones.reintentar) {
                Label("Reintentar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(BotonSecundario(compacto: true))
            .help("Vuelve a dejarla pendiente para el próximo «Procesar»")
        case .hecha:
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([fila.archivoParaMostrar])
            } label: {
                Label("Mostrar", systemImage: "folder")
            }
            .buttonStyle(BotonSecundario(compacto: true))
            .help("Mostrar «\(fila.archivoParaMostrar.lastPathComponent)» en el Finder")
        case .listaParaProcesar where fila.plan != nil:
            Button(action: acciones.abrirPistas) {
                Label("Pistas ✓", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(BotonSecundario(compacto: true))
            .help("Ya armaste el MKV de esta fila: «Procesar» lo crea. Toca para cambiarlo")
        default:
            EmptyView()
        }
    }
}

/// Cápsula de color con texto, para el estado de una fila.
struct EtiquetaSimple: View {
    let texto: String
    let icono: String?
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            if let icono {
                Image(systemName: icono).font(.system(size: 10, weight: .bold))
            } else {
                ProgressView().controlSize(.mini)
            }
            Text(texto).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
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
    var sinScroll = false
    @State private var eligiendoCarpeta = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                TarjetaCarpeta(icono: "tray.and.arrow.down.fill", titulo: "Carpeta vigilada", color: Tema.ambar,
                               url: vigilante.carpeta) { eligiendoCarpeta = true }
                    .frame(maxWidth: 360)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vigilante.activo ? "Vigilando" : (vigilante.carpeta == nil ? "Elige una carpeta" : "Apagada"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(vigilante.activo ? Tema.verde : Tema.tinta)
                    Text("Cada 30 segundos mira la carpeta y procesa sola cada película que termine de bajar, "
                         + "con las mismas opciones de «Subtítulos». Te avisa con una notificación.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            if vigilante.historial.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Tema.morado.opacity(0.10)).frame(width: 100, height: 100)
                        Image(systemName: vigilante.activo ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(Tema.degradado)
                            .symbolEffect(.pulse, isActive: vigilante.activo)
                    }
                    Text(vigilante.activo
                         ? "Vigilando. Las películas nuevas se procesarán solas."
                         : "La vigilancia está apagada. Enciéndela arriba a la derecha.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.tintaSuave)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sinScroll {
                historial.frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView { historial }
            }
        }
        .fileImporter(isPresented: $eligiendoCarpeta, allowedContentTypes: [.folder]) { resultado in
            if case .success(let url) = resultado { vigilante.carpeta = url }
        }
    }

    private var historial: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LO ÚLTIMO")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Tema.acento)
                .padding(.leading, 4)
            ForEach(vigilante.historial) { anotacion in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: anotacion.bien ? "checkmark" : "exclamationmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(anotacion.bien ? Tema.verde : Tema.ambar))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(anotacion.nombre)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tema.tinta)
                            .lineLimit(1).truncationMode(.middle)
                        Text(anotacion.texto)
                            .font(.system(size: 12))
                            .foregroundStyle(Tema.tintaSuave)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(anotacion.cuando, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.tintaSuave.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .tarjeta(radio: 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

// MARK: - Aviso

struct AvisoDeHerramientas: View {
    let mensaje: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tema.ambar)
            Text(mensaje).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Tema.tinta)
            Spacer()
        }
        .padding(12)
        .background(Tema.tarjeta)
        .overlay(alignment: .top) { Rectangle().fill(Tema.borde).frame(height: 1) }
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
            Text("Pistas del MKV")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Tema.tinta)
            Text(video.lastPathComponent)
                .font(.callout).foregroundStyle(Tema.tintaSuave)
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
                .font(.callout).foregroundStyle(Tema.tintaSuave)
            }
            .groupBoxStyle(GrupoEnTarjeta())
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
                        .buttonStyle(BotonSecundario(compacto: true))
                } else if planActual != nil {
                    Button("Quitar el plan") { alGuardar(nil); cerrar() }
                        .buttonStyle(BotonSecundario(compacto: true))
                        .help("«Procesar» volverá a extraer el .srt como siempre")
                }
                Spacer()
                Button(resultado == nil ? "Cancelar" : "Cerrar") { cerrar() }
                    .buttonStyle(BotonSecundario())
                    .keyboardShortcut(.cancelAction)
                    .disabled(trabajando)
                if resultado == nil {
                    if pendiente {
                        Button("Guardar para Procesar") { alGuardar(plan); cerrar() }
                            .buttonStyle(BotonPrincipal())
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
                    .buttonStyle(CrearMKVEstilo(principal: !pendiente))
                    .disabled(trabajando || leyendo || audiosMarcados.isEmpty)
                }
            }
        }
        .padding(22)
        .frame(width: 880, height: 640)
        .background(Tema.fondo)
        .tint(Tema.morado)
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

/// Los recuadros de la hoja de pistas como tarjetas blancas con título morado.
struct GrupoEnTarjeta: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            configuration.label
                .font(.system(size: 10.5, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Tema.acento)
            configuration.content
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Tema.tarjeta))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tema.borde, lineWidth: 1))
        }
    }
}

/// «Crear MKV ahora» es el botón principal si no hay plan que guardar; si lo hay, el secundario.
struct CrearMKVEstilo: ButtonStyle {
    let principal: Bool
    func makeBody(configuration: Configuration) -> some View {
        if principal {
            BotonPrincipal().makeBody(configuration: configuration)
        } else {
            BotonSecundario().makeBody(configuration: configuration)
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

    private let claro = Color(suave: 0.30, green: 0.85, blue: 0.42)
    private let oscuro = Color(suave: 0.10, green: 0.62, blue: 0.27)

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

    private let verde = Color(suave: 0.20, green: 0.78, blue: 0.35)

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
