import AppKit
import SubFixKit
import SwiftUI

// MARK: - Modelo

/// Un video en la pestaña «Pistas»: lo que trae dentro y lo último que se le hizo.
public struct VideoConPistas: Identifiable, Equatable {
    public let id = UUID()
    public internal(set) var url: URL
    var audios: [PistaDeAudio] = []
    var subtitulos: [Pista] = []
    /// Latino, España, forzado, para sordos: leído del texto (llega un momento después de las pistas).
    var variantes: [Int: Variante] = [:]
    var estado: Estado = .leyendo
    /// El MKV que SubFix hizo a partir de este video: si existe, este es «el viejo».
    var versionNueva: URL?

    enum Estado: Equatable {
        case leyendo
        case listo
        case trabajando
        case hecho(String)
        case aviso(String)
        case fallo(String)

        var texto: String? {
            switch self {
            case .hecho(let t), .aviso(let t), .fallo(let t): return t
            case .leyendo: return "leyendo las pistas…"
            case .trabajando: return "cambiando…"
            case .listo: return nil
            }
        }

        var color: Color {
            switch self {
            case .hecho: return Tema.verde
            case .aviso: return Tema.ambar
            case .fallo: return Tema.rojo
            default: return Tema.tintaSuave
            }
        }
    }

    var visible: NombreVisible { NombreVisible(url) }
    var esMKV: Bool { url.pathExtension.lowercased() == "mkv" }
}

/// La lista de la pestaña «Pistas». Aparte de la de «Subtítulos»: aquí no se busca nada
/// en internet, sólo se mira y se cambia lo que el archivo ya trae.
@MainActor
public final class ColaDePistas: ObservableObject {
    @Published public var videos: [VideoConPistas] = []
    @Published public var trabajando = false
    @Published public var nota: String?

    public init() {}

    public func agregar(_ rutas: [URL]) {
        let nuevos = Motor.videos(en: rutas)
            .filter { url in !videos.contains { $0.url == url } }
            .map { VideoConPistas(url: $0) }
        videos.append(contentsOf: nuevos)
        for video in nuevos { leer(video.id) }
        for i in videos.indices where videos[i].versionNueva == nil {
            videos[i].versionNueva = Papelera.versionDeSubFix(de: videos[i].url)
        }
    }

    func leer(_ id: UUID) {
        guard let url = videos.first(where: { $0.id == id })?.url else { return }
        Task.detached(priority: .userInitiated) {
            let audios = (try? Sondeo.audios(de: url)) ?? []
            let subtitulos = (try? Sondeo.pistas(de: url)) ?? []
            await MainActor.run {
                self.cambiar(id) { v in
                    v.audios = audios
                    v.subtitulos = subtitulos
                    if v.estado == .leyendo { v.estado = audios.isEmpty && subtitulos.isEmpty ? .fallo("no pude leer sus pistas") : .listo }
                }
            }
            guard subtitulos.contains(where: Clasificador.seLee) else { return }
            let variantes = Clasificador.clasificar(subtitulos, de: url)
            await MainActor.run { self.cambiar(id) { $0.variantes = variantes } }
        }
    }

    private func cambiar(_ id: UUID, _ cambio: (inout VideoConPistas) -> Void) {
        guard let i = videos.firstIndex(where: { $0.id == id }) else { return }
        cambio(&videos[i])
    }

    public func quitar(_ id: UUID) { videos.removeAll { $0.id == id } }
    public func vaciar() { videos.removeAll { $0.estado != .trabajando } }

    /// La hoja creó un MKV nuevo a partir de este video: se anota y se agrega a la lista.
    func mkvCreado(_ id: UUID, _ mkv: URL) {
        cambiar(id) { $0.estado = .hecho("MKV nuevo: \(mkv.lastPathComponent)"); $0.versionNueva = mkv }
        agregar([mkv])
    }

    /// Manda el video y sus .srt sueltos a la Papelera (se recuperan con «Devolver») y lo quita de la lista.
    func aLaPapelera(_ id: UUID) {
        guard let video = videos.first(where: { $0.id == id }), video.estado != .trabajando else { return }
        do {
            let enviados = try Papelera.enviar(video.url)
            videos.removeAll { $0.id == id }
            let subs = enviados.count - 1
            nota = "«\(video.url.lastPathComponent)»" + (subs > 0 ? " y \(subs) subtítulo\(subs == 1 ? "" : "s")" : "")
                + " a la Papelera. Si te equivocaste, ábrela y usa «Devolver»."
        } catch {
            cambiar(id) { $0.estado = .fallo(error.localizedDescription) }
        }
    }

    public var paraLatino: [VideoConPistas] { videos.filter { $0.esMKV && $0.estado != .leyendo && $0.estado != .trabajando } }

    /// «Latino por defecto»: deja automático el subtítulo latino y, si lo trae, el audio
    /// latino. Cambia el MISMO archivo (sólo la cabecera, en un segundo).
    public func latinoPorDefecto(_ ids: [UUID]) {
        guard !trabajando else { return }
        let porHacer = paraLatino.filter { ids.contains($0.id) }
        guard !porHacer.isEmpty else { return }
        trabajando = true
        Task {
            var cambiados = 0, yaEstaban = 0, sinLatino = 0, fallos = 0
            for video in porHacer {
                let url = video.url, id = video.id
                cambiar(id) { $0.estado = .trabajando }
                do {
                    let resultado = try await Task.detached(priority: .userInitiated) {
                        try CabeceraMKV.latinoPorDefecto(url)
                    }.value
                    switch resultado {
                    case .cambiado(let texto): cambiados += 1; cambiar(id) { $0.estado = .hecho(texto) }
                    case .yaEstaba(let texto): yaEstaban += 1; cambiar(id) { $0.estado = .hecho(texto) }
                    case .sinLatino: sinLatino += 1; cambiar(id) { $0.estado = .aviso("no trae subtítulo ni audio latino") }
                    }
                } catch {
                    fallos += 1
                    cambiar(id) { $0.estado = .fallo(error.localizedDescription) }
                }
                leer(id)
            }
            trabajando = false
            guard porHacer.count > 1 else { return }
            var partes: [String] = []
            if cambiados > 0 { partes.append("\(cambiados) con latino por defecto") }
            if yaEstaban > 0 { partes.append("\(yaEstaban) ya estaban así") }
            if sinLatino > 0 { partes.append("\(sinLatino) sin latino dentro") }
            if fallos > 0 { partes.append("\(fallos) no se pudieron") }
            nota = partes.joined(separator: " · ") + "."
        }
    }
}

// MARK: - Vista

/// Pestaña «Pistas»: qué audios y subtítulos trae cada película, cuál sale por defecto,
/// y desde aquí se arma un MKV a medida o se deja el latino por defecto.
struct VistaPistas: View {
    @ObservedObject var cola: ColaDePistas
    var sinScroll = false
    @State private var encima = false
    @State private var editando: VideoConPistas?
    @State private var paraPapelera: VideoConPistas?

    var body: some View {
        VStack(spacing: 0) {
            if cola.videos.isEmpty {
                vacia
            } else {
                encabezado
                if sinScroll {
                    lista.frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView { lista }
                }
            }
            if let nota = cola.nota {
                Franja(texto: nota, icono: "checkmark.circle.fill", color: Tema.verde) { cola.nota = nil }
            }
            barra
        }
        .onDrop(of: [.fileURL], isTargeted: $encima) { proveedores in
            Task { @MainActor in
                var rutas: [URL] = []
                for proveedor in proveedores {
                    let url = await withCheckedContinuation { (seguir: CheckedContinuation<URL?, Never>) in
                        _ = proveedor.loadObject(ofClass: URL.self) { url, _ in seguir.resume(returning: url) }
                    }
                    if let url { rutas.append(url) }
                }
                cola.agregar(rutas)
            }
            return true
        }
        .alert("¿Mandar a la Papelera?", isPresented: Binding(get: { paraPapelera != nil },
                                                               set: { if !$0 { paraPapelera = nil } }),
               presenting: paraPapelera) { video in
            Button("Mandar a la Papelera", role: .destructive) { cola.aLaPapelera(video.id) }
            Button("Cancelar", role: .cancel) {}
        } message: { video in
            Text(textoDePapelera(video.url, versionNueva: video.versionNueva))
        }
        .sheet(item: $editando) { video in
            HojaDeMKV(video: video.url, planActual: nil, pendiente: false,
                      alGuardar: { _ in }, alCrear: { cola.mkvCreado(video.id, $0) },
                      variantesConocidas: video.variantes)
        }
    }

    private var vacia: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Tema.morado.opacity(0.10)).frame(width: 110, height: 110)
                Circle().fill(Tema.morado.opacity(0.08)).frame(width: 150, height: 150)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Tema.degradado)
            }
            VStack(spacing: 6) {
                Text("Arrastra películas para ver sus pistas")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.tinta)
                Text("Qué audios y subtítulos trae cada una y cuál sale por defecto. Desde aquí dejas el "
                     + "latino por defecto o armas un MKV nuevo sólo con las pistas que quieras.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.tintaSuave)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Button(action: explorar) { Label("Añadir…", systemImage: "plus") }
                .buttonStyle(BotonPrincipal())
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(encima ? AnyShapeStyle(Tema.degradado) : AnyShapeStyle(Tema.borde),
                              style: StrokeStyle(lineWidth: encima ? 3 : 2, dash: [10, 6]))
                .padding(20)
        }
    }

    private var encabezado: some View {
        HStack {
            Text(cola.videos.count == 1 ? "1 video" : "\(cola.videos.count) videos")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Tema.tinta)
            Text("★ = la que sale sola al abrirlo")
                .font(.system(size: 11.5))
                .foregroundStyle(Tema.tintaSuave)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private var lista: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cola.videos) { video in
                FilaDePistas(video: video,
                             editar: { editando = video },
                             latino: { cola.latinoPorDefecto([video.id]) },
                             quitar: { cola.quitar(video.id) },
                             papelera: { paraPapelera = video },
                             ocupada: cola.trabajando)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var barra: some View {
        HStack(spacing: 8) {
            Button(action: explorar) { Label("Añadir…", systemImage: "plus") }
                .buttonStyle(BotonSecundario(compacto: true))
                .disabled(cola.trabajando)
                .help("Elegir películas o carpetas. También puedes arrastrarlas")

            if cola.paraLatino.count > 1 {
                Button {
                    cola.latinoPorDefecto(cola.paraLatino.map(\.id))
                } label: {
                    Label("Latino por defecto en todos", systemImage: "globe.americas")
                }
                .buttonStyle(BotonSecundario(compacto: true))
                .disabled(cola.trabajando)
                .help("En cada MKV de la lista deja automático el subtítulo latino y, si lo trae, el audio latino. "
                      + "Cambia el mismo archivo (sólo la cabecera); no crea otro")
            }

            Spacer(minLength: 8)

            if !cola.videos.isEmpty {
                Button("Vaciar lista") { cola.vaciar() }
                    .buttonStyle(BotonSecundario(compacto: true))
                    .disabled(cola.trabajando)
                    .help("Quita todo de la lista. No toca ningún archivo")
            }
        }
        .modifier(FondoDeBarra())
    }

    private func explorar() {
        let panel = NSOpenPanel()
        panel.title = "Elegir películas o carpetas"
        panel.prompt = "Añadir"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { cola.agregar(panel.urls) }
    }
}

struct FilaDePistas: View {
    let video: VideoConPistas
    let editar: () -> Void
    let latino: () -> Void
    let quitar: () -> Void
    let papelera: () -> Void
    let ocupada: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconoDeTipo(esSerie: video.visible.codigo != nil, latiendo: video.estado == .trabajando)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let codigo = video.visible.codigo { Chip(texto: codigo, color: Tema.acentoSerie) }
                    Text(video.visible.titulo.isEmpty ? video.url.lastPathComponent : video.visible.titulo)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tema.tinta)
                        .lineLimit(1).truncationMode(.middle)
                    if let chip = etiquetaDeVersion(video.url, versionNueva: video.versionNueva) { chip }
                }
                .help(video.url.path)

                if video.estado == .leyendo {
                    ProgressView().controlSize(.small)
                } else {
                    renglon("Audio", icono: "speaker.wave.2.fill",
                            video.audios.map { (nombre(idioma: $0.idioma, titulo: $0.titulo), $0.porDefecto) })
                    renglon("Subtítulos", icono: "captions.bubble",
                            video.subtitulos.map { pista in
                                var n = nombre(idioma: pista.idioma, titulo: pista.titulo)
                                if let v = video.variantes[pista.indice] {
                                    // «español · latino · forzado»: lo leído del texto, sin repetir lo que ya dice el título.
                                    for etiqueta in v.etiquetas.map({ $0.lowercased() })
                                        where !n.lowercased().contains(etiqueta.prefix(5)) { n += " · \(etiqueta)" }
                                } else if pista.forzada, !n.lowercased().contains("forz"), !n.lowercased().contains("forced") {
                                    n += " (forzado)"
                                }
                                if pista.esImagen { n += " · imagen" }
                                return (n, pista.porDefecto)
                            })
                }

                if let texto = video.estado.texto, video.estado != .leyendo {
                    Text(texto)
                        .font(.system(size: 12))
                        .foregroundStyle(video.estado.color)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Button(action: editar) { Label("Editar pistas…", systemImage: "slider.horizontal.3") }
                    .buttonStyle(BotonSecundario(compacto: true))
                    .disabled(video.estado == .leyendo || video.estado == .trabajando)
                    .help("Elegir qué audios y subtítulos quedan, cambiarles el idioma o añadir un .srt. "
                          + "Crea un MKV nuevo al lado; el original no se toca")
                if video.esMKV {
                    Button(action: latino) { Label("Latino por defecto", systemImage: "globe.americas") }
                        .buttonStyle(BotonSecundario(compacto: true))
                        .disabled(ocupada || video.estado == .leyendo)
                        .help("Deja automático el subtítulo latino y, si lo trae, el audio latino. "
                              + "Cambia este mismo archivo (sólo la cabecera, en un segundo)")
                }
                if VLC.instalado {
                    Button { VLC.abrir(video.url) } label: { Label("Ver en VLC", systemImage: "play.fill") }
                        .buttonStyle(BotonSecundario(compacto: true))
                        .help("Vista previa: abre este video en VLC (con su .srt de al lado, si tiene)")
                }
                if video.versionNueva != nil {
                    Button(action: papelera) { Label("Papelera…", systemImage: "trash") }
                        .buttonStyle(BotonSecundario(compacto: true))
                        .disabled(video.estado == .trabajando)
                        .help("Ya tiene su versión de SubFix: manda este original y sus .srt a la Papelera")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .tarjeta()
        .contextMenu {
            Button("Editar pistas…", action: editar)
            if video.esMKV { Button("Latino por defecto", action: latino).disabled(ocupada) }
            Divider()
            if VLC.instalado { Button("Ver en VLC") { VLC.abrir(video.url) } }
            Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([video.url]) }
            Button("Quitar de la lista", action: quitar)
            Divider()
            Button("Mandar a la Papelera…", action: papelera).disabled(video.estado == .trabajando)
        }
    }

    /// «Español (Latinoamérica)», «inglés», «sin idioma».
    private func nombre(idioma: String?, titulo: String?) -> String {
        let nombres = ["spa": "español", "eng": "inglés", "por": "portugués", "fre": "francés", "fra": "francés",
                       "ita": "italiano", "ger": "alemán", "deu": "alemán", "jpn": "japonés", "kor": "coreano",
                       "chi": "chino", "zho": "chino", "rus": "ruso", "pol": "polaco"]
        let base = Idioma.estaSinEspecificar(idioma) ? "sin idioma" : (nombres[idioma ?? ""] ?? idioma ?? "?")
        if let titulo, !titulo.isEmpty, titulo.lowercased() != base { return "\(base) · \(titulo)" }
        return base
    }

    private func renglon(_ titulo: String, icono: String, _ pistas: [(String, Bool)]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icono).font(.system(size: 10)).foregroundStyle(Tema.acento).frame(width: 14)
            if pistas.isEmpty {
                Text("ninguno").font(.system(size: 11.5)).foregroundStyle(Tema.tintaSuave)
            } else {
                // Muchas pistas (Spider-Man trae 39 subtítulos): se resumen para no ocupar media pantalla.
                let vistas = pistas.count > 8 ? Array(pistas.filter(\.1) + pistas.filter { !$0.1 }.prefix(6)) : pistas
                Text(vistas.map { ($0.1 ? "★ " : "") + $0.0 }.joined(separator: "   ")
                     + (pistas.count > vistas.count ? "   +\(pistas.count - vistas.count) más" : ""))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tema.tintaSuave)
                    .lineLimit(2)
            }
        }
        .help(pistas.map { ($0.1 ? "★ " : "") + $0.0 }.joined(separator: "\n"))
    }
}

/// Lo que se va a la Papelera (con tamaño) y lo que se queda, para decidir sin abrir el Finder.
/// Lo usan el Editor de video y Subtítulos.
func textoDePapelera(_ video: URL, versionNueva: URL?) -> String {
    func tamaño(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    var lineas = ["Se van:", "• \(video.lastPathComponent) (\(tamaño(video)))"]
    lineas += Papelera.acompañantes(de: video).map { "• \($0.lastPathComponent)" }
    if let nueva = versionNueva, FileManager.default.fileExists(atPath: nueva.path) {
        lineas += ["", "Se queda: \(nueva.lastPathComponent) (\(tamaño(nueva)))"]
    }
    lineas += ["", "Puedes recuperarlos desde la Papelera con «Devolver»."]
    return lineas.joined(separator: "\n")
}

/// El formato de cada video («MKV», «MP4»…); además «SubFix · MKV» en el que creó SubFix y
/// «Original · MP4» en el que ya tiene su versión nueva: dos filas con el mismo título se
/// distinguen sin pasar el ratón.
func etiquetaDeVersion(_ url: URL, versionNueva: URL?) -> Chip? {
    let ext = url.pathExtension.uppercased()
    if url.deletingPathExtension().lastPathComponent.contains(" (SubFix"), ext == "MKV" {
        return Chip(texto: "SubFix · MKV", color: Tema.verde)
    }
    if versionNueva != nil { return Chip(texto: "Original · \(ext)", color: Tema.tintaSuave) }
    return ext.isEmpty ? nil : Chip(texto: ext, color: Tema.tintaSuave)
}

/// Vista previa: abrir el video en VLC, que lee MKV, eac3, Dolby Vision… y carga solo
/// el .srt de al lado. (AVPlayer, el de macOS, no abre MKV.) Sin VLC, el botón no sale.
enum VLC {
    static var app: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.videolan.vlc") }
    static var instalado: Bool { app != nil }
    static func abrir(_ video: URL) {
        guard let app else { return }
        NSWorkspace.shared.open([video], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
