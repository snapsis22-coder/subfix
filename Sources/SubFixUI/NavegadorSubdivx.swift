import AppKit
import OSLog
import SubFixKit
import SwiftUI
import WebKit

/// `log show --predicate 'subsystem == "com.snapsis.subfix"' --info --last 10m` para seguir el recorrido.
let registroSubdivx = Logger(subsystem: "com.snapsis.subfix", category: "subdivx")

/// Un capítulo o una película que buscar en Subdivx.
public struct TrabajoSubdivx: Identifiable, Equatable {
    public let id: UUID            // el de su fila
    public let video: URL
    public let busqueda: String    // lo que se escribe en el buscador: «Ted Lasso S03E11», «The Batman 2022»
    public let titulo: String      // la serie o la película, para reconocer el resultado: «Ted Lasso»
    public let codigo: String?     // «S03E11»
    public let año: String?
    public let etiqueta: String    // cómo se ve en la columna: «S03E11 · Mom City»

    public init(fila: Fila) {
        let visible = fila.visible
        let base = Motor.busquedaSubdivx(para: fila.url)
        id = fila.id
        video = fila.url
        codigo = visible.codigo
        año = visible.año
        if let codigo = visible.codigo {
            titulo = base.replacingOccurrences(of: codigo, with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            busqueda = base
        } else {
            // Sin el año, «The Batman» trae 200 Batman y el de 2022 ni aparece.
            titulo = base
            busqueda = visible.año.map { "\(base) \($0)" } ?? base
        }
        etiqueta = [visible.codigo, visible.titulo.isEmpty ? nil : visible.titulo]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// Lo que se abre en la hoja: uno o varios trabajos.
struct LoteSubdivx: Identifiable {
    let id = UUID()
    let trabajos: [TrabajoSubdivx]
}

/// Subdivx dentro de la app, recorriendo solo los capítulos que faltan.
///
/// Su Cloudflare bloquea a los programas (`403 cf-mitigated: challenge`) y eso no se
/// esquiva: esto es un navegador de verdad, a la vista, y si aparece «Verifica que eres
/// humano» lo marca el usuario. Hecho eso, SubFix usa la página como lo haría una
/// persona: escribe la búsqueda, elige el resultado de ese capítulo y baja su .srt
/// latino, uno por uno y respetando el ritmo que el propio sitio pide.
struct HojaDeSubdivx: View {
    let lote: LoteSubdivx
    /// Lo bajado y la fila a la que va (nil si se bajó a mano y no se sabe). `true` si traía .srt.
    let alDescargar: (URL, UUID?) -> Bool
    @Environment(\.dismiss) private var cerrar
    @StateObject private var navegador = Navegador()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { navegador.web.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!navegador.puedeVolver)
                    .help("Atrás")
                Button { navegador.web.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Recargar")

                VStack(alignment: .leading, spacing: 2) {
                    Text(lote.trabajos.count == 1 ? "Subdivx · \(lote.trabajos[0].busqueda)"
                                                  : "Subdivx · \(lote.trabajos.count) por buscar")
                        .font(.headline).lineLimit(1)
                    Text(navegador.estado).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }

                Spacer()

                if navegador.recorriendo {
                    Button("Detener") { navegador.detener() }
                        .help("Termina el que está bajando y para. Después puedes buscar y bajar a mano")
                }
                Button(navegador.terminado ? "Listo" : "Cerrar") { cerrar() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)

            Divider()

            HStack(spacing: 0) {
                if lote.trabajos.count > 1 {
                    columna
                    Divider()
                }
                VistaWeb(web: navegador.web)
            }
        }
        .frame(width: lote.trabajos.count > 1 ? 1180 : 1000, height: 740)
        .onAppear {
            navegador.alDescargar = alDescargar
            navegador.alTerminarBien = { cerrar() }
            navegador.empezar(lote.trabajos)
        }
        .onDisappear { navegador.detener() }
    }

    /// Cada trabajo con su estado, para ver en qué va.
    private var columna: some View {
        List(lote.trabajos) { trabajo in
            HStack(spacing: 8) {
                icono(navegador.resultados[trabajo.id] ?? .pendiente)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(trabajo.etiqueta).lineLimit(1)
                    if let texto = (navegador.resultados[trabajo.id] ?? .pendiente).texto {
                        Text(texto).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.sidebar)
        .frame(width: 240)
    }

    @ViewBuilder private func icono(_ resultado: Navegador.Resultado) -> some View {
        switch resultado {
        case .pendiente: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .buscando: ProgressView().controlSize(.small)
        case .bajado: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .sinLatino, .noEncontrado: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .fallo: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}

private struct VistaWeb: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ vista: WKWebView, context: Context) {}
}

@MainActor
final class Navegador: NSObject, ObservableObject {
    enum Resultado: Equatable {
        case pendiente, buscando
        case bajado(String)
        case sinLatino
        case noEncontrado
        case fallo(String)

        var texto: String? {
            switch self {
            case .pendiente: return nil
            case .buscando: return "buscando…"
            case .bajado(let archivo): return archivo
            case .sinLatino: return "en Subdivx no hay latino"
            case .noEncontrado: return "no está en Subdivx"
            case .fallo(let motivo): return motivo
            }
        }
    }

    static let inicio = "https://www.subdivx.com/"
    /// El sitio responde «espera unos segundos antes de realizar otra búsqueda» si se va más rápido.
    static let pausaEntreBusquedas: TimeInterval = 8

    let web: WKWebView
    @Published var puedeVolver = false
    @Published var estado = "Abriendo Subdivx… Si sale «Verifica que eres humano», márcalo."
    @Published private(set) var resultados: [UUID: Resultado] = [:]
    @Published private(set) var recorriendo = false
    @Published private(set) var terminado = false
    var alDescargar: ((URL, UUID?) -> Bool)?
    var alTerminarBien: (() -> Void)?

    private var trabajos: [TrabajoSubdivx] = []
    private var actual: UUID?
    private var detenido = false
    private var ultimaBusqueda: Date?
    private var esperandoDescarga: CheckedContinuation<URL?, Never>?
    private var destinos: [ObjectIdentifier: URL] = [:]
    private let carpeta = FileManager.default.temporaryDirectory
        .appendingPathComponent("subfix-subdivx-\(UUID().uuidString)")
    private var observador: NSKeyValueObservation?

    override init() {
        let configuracion = WKWebViewConfiguration()
        // Almacén persistente: la verificación de Cloudflare y las cookies
        // sobreviven entre sesiones, como en un navegador normal.
        configuracion.websiteDataStore = .default()
        configuracion.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        web = WKWebView(frame: .zero, configuration: configuracion)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        observador = web.observe(\.canGoBack) { [weak self] web, _ in
            Task { @MainActor in self?.puedeVolver = web.canGoBack }
        }
    }

    func empezar(_ trabajos: [TrabajoSubdivx]) {
        self.trabajos = trabajos
        for trabajo in trabajos { resultados[trabajo.id] = .pendiente }
        web.load(URLRequest(url: URL(string: Self.inicio)!))
        Task { await recorrer() }
    }

    func detener() {
        guard !detenido else { return }
        detenido = true
        resolverDescarga(nil)
        if recorriendo { estado = "Detenido: puedes buscar y bajar a mano; lo que bajes se instala igual." }
    }

    // MARK: Recorrido

    private func recorrer() async {
        guard !recorriendo else { return }
        recorriendo = true
        for trabajo in trabajos where resultados[trabajo.id] == .pendiente {
            if detenido { break }
            actual = trabajo.id
            resultados[trabajo.id] = .buscando
            let resultado = await buscarYBajar(trabajo)
            resultados[trabajo.id] = resultado
        }
        actual = nil
        recorriendo = false
        guard !detenido else { return }
        terminar()
    }

    private func terminar() {
        terminado = true
        let todos = trabajos.compactMap { resultados[$0.id] }
        func cuantos(_ es: (Resultado) -> Bool) -> Int { todos.filter(es).count }
        let bajados = cuantos { if case .bajado = $0 { return true } else { return false } }
        let sinLatino = cuantos { $0 == .sinLatino }
        let noEstan = cuantos { $0 == .noEncontrado }
        let fallos = cuantos { if case .fallo = $0 { return true } else { return false } }
        if bajados == todos.count {
            estado = bajados == 1 ? "Listo: quedó el latino." : "Listo: los \(bajados) quedaron con el latino."
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                alTerminarBien?()
            }
        } else {
            let partes = [bajados > 0 ? "\(bajados) con latino" : nil,
                          sinLatino > 0 ? "\(sinLatino) sin latino en Subdivx" : nil,
                          noEstan > 0 ? "\(noEstan) no está\(noEstan == 1 ? "" : "n") en Subdivx" : nil,
                          fallos > 0 ? "\(fallos) con error" : nil].compactMap { $0 }
            estado = "Terminé: " + partes.joined(separator: ", ")
                + ". Puedes buscar a mano: lo que bajes se instala."
        }
    }

    private func buscarYBajar(_ trabajo: TrabajoSubdivx) async -> Resultado {
        let numero = (trabajos.firstIndex(of: trabajo) ?? 0) + 1
        for _ in 0..<5 {
            if let ultima = ultimaBusqueda {
                let falta = Self.pausaEntreBusquedas - Date().timeIntervalSince(ultima)
                if falta > 0 {
                    estado = "Esperando unos segundos (Subdivx no deja buscar tan seguido)…"
                    try? await Task.sleep(for: .seconds(falta))
                }
            }
            guard await esperarPagina() else { return .fallo("Subdivx no terminó de cargar") }
            if detenido { return .pendiente }

            estado = trabajos.count == 1 ? "Buscando «\(trabajo.busqueda)»…"
                                         : "Buscando \(numero) de \(trabajos.count): «\(trabajo.busqueda)»…"
            ultimaBusqueda = Date()
            let respuesta: [String: Any]
            do {
                respuesta = try await web.callAsyncJavaScript(
                    Self.elegir,
                    arguments: ["q": trabajo.busqueda, "codigo": trabajo.codigo ?? "",
                                "anio": trabajo.año ?? "", "titulo": trabajo.titulo,
                                "nombre": trabajo.video.deletingPathExtension().lastPathComponent],
                    contentWorld: .page) as? [String: Any] ?? [:]
            } catch {
                respuesta = ["estado": "error", "mensaje": error.localizedDescription]
            }

            registroSubdivx.notice("""
                \(trabajo.busqueda, privacy: .public) → \(respuesta["estado"] as? String ?? "?", privacy: .public) \
                \(respuesta["archivo"] as? String ?? "", privacy: .public) \(respuesta["mensaje"] as? String ?? "", privacy: .public)
                """)
            switch respuesta["estado"] as? String {
            case "archivo":
                // Se baja el paquete entero, como el botón «Bajar subtítulo ahora»: el atajo
                // de un solo archivo (`dc=1&archivo=…`) falla con eñes y tildes y devuelve
                // «No se pudo extraer el archivo. Error técnico.». Del paquete, SubFix se
                // queda con el latino (`Motor.emparejar`).
                let archivo = respuesta["archivo"] as? String ?? "subtítulo"
                if let id = respuesta["id"] as? String, id.allSatisfy(\.isNumber) {
                    estado = "Bajando «\(respuesta["titulo"] as? String ?? trabajo.busqueda)»…"
                    if let bajado = await bajar(paquete: id), alDescargar?(bajado, trabajo.id) == true {
                        return .bajado(archivo)
                    }
                }
                return .fallo("la descarga no trajo el .srt")
            case "esperar", "noListo":
                try? await Task.sleep(for: .seconds(6))
            case "sinLatino":
                return .sinLatino
            case "sinResultados":
                return .noEncontrado
            default:
                return .fallo(respuesta["mensaje"] as? String ?? "respuesta inesperada de Subdivx")
            }
        }
        return .fallo("Subdivx no respondió a tiempo")
    }

    /// Hasta que la página tenga su buscador y su clave. Si sale la verificación de
    /// Cloudflare, la espera es la del usuario.
    private func esperarPagina() async -> Bool {
        let inicio = Date()
        var recargada = false
        while !detenido {
            let lista = (try? await web.evaluateJavaScript(
                "typeof jQuery !== 'undefined' && !!document.getElementById('buscar') "
                + "&& typeof searchToken !== 'undefined' && !!searchToken")) as? Bool ?? false
            if lista { return true }
            let pasado = Date().timeIntervalSince(inicio)
            if pasado > 4 { estado = "Si sale «Verifica que eres humano», márcalo: después sigo solo." }
            // Si quedó en otra página (p. ej. el usuario navegó), volver a la portada.
            if pasado > 10, !recargada, web.url?.path != "/" {
                recargada = true
                web.load(URLRequest(url: URL(string: Self.inicio)!))
            }
            if pasado > 300 { return false }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    /// La descarga la pide la propia página (como un clic: con su Referer y sus cookies).
    private func bajar(paquete id: String) async -> URL? {
        registroSubdivx.notice("pido el paquete \(id, privacy: .public)")
        return await withCheckedContinuation { continuacion in
            esperandoDescarga = continuacion
            web.evaluateJavaScript("window.location.href = 'descargar.php?f=1&id=\(id)';", completionHandler: nil)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                self?.resolverDescarga(nil)
            }
        }
    }

    private func resolverDescarga(_ archivo: URL?) {
        guard let continuacion = esperandoDescarga else { return }
        esperandoDescarga = nil
        continuacion.resume(returning: archivo)
    }

    /// Lo que corre DENTRO de la página, como cuerpo de una función asíncrona con
    /// `q`, `codigo`, `anio`, `titulo` y `nombre` (el del video). Usa el buscador y la tabla del propio sitio
    /// (`#buscar`, `#btnSrch`, la variable global `tabla`) y su lista de archivos de
    /// cada subtítulo (`getContenidoSub`) para confirmar que el paquete trae el latino.
    /// Probado contra subdivx.com v4.29 (10-oct-2026).
    static let elegir = #"""
    const $ = window.jQuery;
    if (!$ || !$('#buscar').length || !$('#btnSrch').length || typeof searchToken === 'undefined' || !searchToken)
      return { estado: 'noListo' };
    $('#buscar').val(q).trigger('input');
    $('#btnSrch').trigger('click');
    const t = window.tabla;
    await new Promise(res => {
      let listo = false; const fin = () => { if (!listo) { listo = true; res(); } };
      try { t.one('xhr', () => setTimeout(fin, 300)); } catch (e) {}
      const inicio = Date.now();
      const vigilar = setInterval(() => {
        const s = t.settings()[0];
        if ((s && s.json) || Date.now() - inicio > 15000) { clearInterval(vigilar); setTimeout(fin, 300); }
      }, 300);
    });
    const json = t.settings()[0].json || {};
    if (/espera/i.test(json.mensaje || '')) return { estado: 'esperar', mensaje: json.mensaje };
    const filas = t.rows().data().toArray();
    if (!filas.length) return { estado: 'sinResultados' };

    const plano = s => String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    const base = s => plano(s).replace(/\(.*$/, '').replace(/\baka\b.*$/, '').replace(/[^a-z0-9]+/g, ' ').trim();
    const cod = plano(codigo);
    const alt = cod ? cod.replace(/^s0?(\d+)e0?(\d+)$/, '$1x$2') : '';
    const alt2 = cod ? cod.replace(/^s0?(\d+)e(\d+)$/, '$1x$2') : '';
    const serie = base(titulo);
    const candidatas = filas.map(f => {
      const texto = plano(f.titulo) + ' ' + plano(f.descripcion) + ' ';
      let p = 0;
      if (cod) {
        // Capítulo: la serie al principio del título y el SxxEyy (o 3x11) en título o descripción.
        if (!base(f.titulo).startsWith(serie)) return null;
        if (!(texto.includes(cod) || texto.includes(alt + ' ') || texto.includes(alt2 + ' '))) return null;
        if (f.pack === '1') p -= 30;
      } else {
        // Película: el título exacto y, si se sabe, el mismo año.
        if (base(f.titulo) !== serie) return null;
        if (anio && !String(f.titulo).includes(anio)) return null;
      }
      if (/latin|latam|latino/.test(texto)) p += 15;
      // Desempate: la versión cuya descripción comparte fichas con el video (2160p, WEB-DL, NF…)
      // es la que va sincronizada con él («Unabomber (2026) - 4K» para un 2160p).
      for (const ficha of new Set(plano(nombre).split(/[^a-z0-9]+/).filter(x => x.length >= 3 && !serie.includes(x))))
        if (texto.includes(ficha)) p += 3;
      p += Math.min(Number(f.descargas) || 0, 20000) / 2000;
      return { id: f.id, titulo: f.titulo, descripcion: f.descripcion, p };
    }).filter(Boolean).sort((a, b) => b.p - a.p).slice(0, 4);

    const deEspana = n => /espa.?a\)|\(espa.?a|castellano|spain|\bes-es\b/i.test(n || '');
    for (const c of candidatas) {
      let archivos = [];
      try { archivos = await $.get('inc/ajax.php', { getContenidoSub: c.id }); } catch (e) {}
      if (!Array.isArray(archivos)) archivos = [];
      const srts = archivos.map(a => a.contenido).filter(n => /\.(srt|ssa|ass)$/i.test(n));
      const etiquetado = srts.find(n => /latin|latam|\blat\b/i.test(n) && !deEspana(n));
      const unico = srts.length === 1 && !deEspana(srts[0]) && !deEspana(c.descripcion) ? srts[0] : null;
      const latino = etiquetado || unico;
      if (latino) return { estado: 'archivo', id: String(c.id), titulo: c.titulo, archivo: latino };
    }
    return { estado: candidatas.length ? 'sinLatino' : 'sinResultados' };
    """#

    private static let extensiones: Set<String> = ["zip", "rar", "7z", "srt"]
}

extension Navegador: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor accion: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(accion.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor respuesta: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let disposicion = (respuesta.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let url = respuesta.response.url
        // descargar.php siempre es una descarga: si mostrara el .srt como texto, la
        // página de búsqueda se perdería.
        let esArchivo = disposicion.contains("attachment") || url?.lastPathComponent == "descargar.php"
            || Self.extensiones.contains(url?.pathExtension.lowercased() ?? "") || !respuesta.canShowMIMEType
        registroSubdivx.notice("""
            respuesta \((respuesta.response as? HTTPURLResponse)?.statusCode ?? 0) \
            \(url?.absoluteString ?? "-", privacy: .public) \(respuesta.response.mimeType ?? "-", privacy: .public) \
            principal=\(respuesta.isForMainFrame) → \(esArchivo ? "descarga" : "mostrar", privacy: .public)
            """)
        decisionHandler(esArchivo ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome descarga: WKDownload) {
        descarga.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome descarga: WKDownload) {
        descarga.delegate = self
    }
}

extension Navegador: WKUIDelegate {
    /// Los enlaces que abren ventana nueva: los de Subdivx (a veces la descarga)
    /// se cargan aquí mismo; los demás —publicidad— se ignoran.
    func webView(_ webView: WKWebView, createWebViewWith configuracion: WKWebViewConfiguration,
                 for accion: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if accion.request.url?.host?.hasSuffix("subdivx.com") == true {
            webView.load(accion.request)
        }
        return nil
    }
}

extension Navegador: WKDownloadDelegate {
    func download(_ descarga: WKDownload, decideDestinationUsing respuesta: URLResponse,
                  suggestedFilename nombre: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        var destino = carpeta.appendingPathComponent(nombre)
        if FileManager.default.fileExists(atPath: destino.path) {
            destino = carpeta.appendingPathComponent("\(UUID().uuidString.prefix(6)) \(nombre)")
        }
        destinos[ObjectIdentifier(descarga)] = destino
        if esperandoDescarga == nil { estado = "Descargando «\(nombre)»…" }
        completionHandler(destino)
    }

    func downloadDidFinish(_ descarga: WKDownload) {
        guard let archivo = destinos.removeValue(forKey: ObjectIdentifier(descarga)) else { return }
        registroSubdivx.notice("bajado \(archivo.lastPathComponent, privacy: .public) esperado=\(self.esperandoDescarga != nil)")
        if esperandoDescarga != nil {
            resolverDescarga(archivo)
            return
        }
        // Bajado a mano: a la fila que se está buscando o, si no hay, a la que le corresponda.
        let para = actual ?? (trabajos.count == 1 ? trabajos.first?.id : nil)
        if alDescargar?(archivo, para) == true {
            if let para { resultados[para] = .bajado(archivo.lastPathComponent) }
            estado = "Instalado «\(archivo.lastPathComponent)»."
        } else {
            estado = "«\(archivo.lastPathComponent)» no traía un .srt para estos videos — prueba con otro."
        }
    }

    func download(_ descarga: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinos.removeValue(forKey: ObjectIdentifier(descarga))
        registroSubdivx.error("descarga falló: \(error.localizedDescription, privacy: .public)")
        if esperandoDescarga != nil {
            resolverDescarga(nil)
        } else {
            estado = "No se pudo descargar: \(error.localizedDescription)"
        }
    }
}
