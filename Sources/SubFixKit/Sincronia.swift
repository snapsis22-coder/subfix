import Accelerate
import Foundation

/// ¿El subtítulo bajado va sincronizado con ESTE video?
///
/// Lo bajado de internet por título (OpenSubtitles, Addic7ed, Subdivx) suele ser de otra
/// versión: otro corte, otra intro, o hecho para 25 fps. Para saberlo se compara contra
/// algo que seguro va con el video:
///
/// 1. **Un subtítulo que el video ya trae dentro** (casi siempre el inglés): aunque sea
///    otro idioma, las frases entran y salen a la vez.
/// 2. Si no trae ninguno, **el audio**: se saca el canal central (donde va la voz) en
///    tres tramos de unos minutos y se marca dónde se habla.
///
/// Las dos cosas se vuelven una señal de 10 muestras por segundo («hay texto/voz o no»)
/// y se busca el desplazamiento —y, por si es de 25 fps, la escala— que mejor las
/// alinea. Si lo mejor es no mover nada, va sincronizado; si es mover lo mismo en toda
/// la película, se puede corregir; si cada tramo pide otra cosa, es otro montaje.
public enum Sincronia {

    static let hz = 10.0
    /// ±2 minutos: más allá ya no es «corrido», es otra película.
    static let busqueda = 1200
    static let umbralLocal: Float = 4
    /// Velocidades típicas de un subtítulo hecho para otra versión (PAL 25, cine 24, NTSC 23,976).
    static let escalas: [Double] = [1, 25 / 23.976, 23.976 / 25, 24 / 23.976, 23.976 / 24, 25 / 24, 24 / 25]

    // MARK: - Resultado

    /// `tiempo bueno = escala × tiempo del subtítulo + desfase`.
    public struct Ajuste: Equatable, Sendable {
        public var escala: Double
        public var desfase: Double

        public init(escala: Double, desfase: Double) {
            self.escala = escala
            self.desfase = desfase
        }

        public static let ninguno = Ajuste(escala: 1, desfase: 0)
        public var cambiaVelocidad: Bool { abs(escala - 1) > 1e-4 }

        /// «iba 2,4 s adelantado», «era de otra velocidad de video».
        public var descripcion: String {
            var partes: [String] = []
            if cambiaVelocidad {
                partes.append(String(format: "era de una versión %@ (%.1f %%)", escala > 1 ? "más rápida" : "más lenta",
                                     abs(escala - 1) * 100).replacingOccurrences(of: ".", with: ","))
            }
            if abs(desfase) >= 0.05 {
                let s = String(format: "%.1f", abs(desfase)).replacingOccurrences(of: ".", with: ",")
                partes.append(desfase > 0 ? "iba \(s) s adelantado" : "iba \(s) s atrasado")
            }
            return partes.isEmpty ? "sin cambios" : partes.joined(separator: " y ")
        }
    }

    public enum Veredicto: Equatable, Sendable {
        /// Va con el video. `con` = contra qué se comprobó («la pista en inglés del archivo»).
        case sincronizado(con: String)
        /// Corrido lo mismo en toda la película: se arregla moviendo los tiempos.
        case corregible(Ajuste, con: String)
        /// Cada parte pide otra cosa, o no se parece en nada: otra versión del video.
        case desfasado(con: String)
        /// No hubo con qué comparar o el resultado no fue claro.
        case sinComprobar(String)

        /// Mayor es mejor, para elegir entre varios bajados.
        public var rango: Int {
            switch self {
            case .sincronizado: return 3
            case .corregible: return 2
            case .sinComprobar: return 1
            case .desfasado: return 0
            }
        }

        public var resumen: String {
            switch self {
            case .sincronizado(let con): return "sincronía comprobada con \(con)"
            case .corregible(let ajuste, let con): return "\(ajuste.descripcion): lo ajusté (comprobado con \(con))"
            case .desfasado(let con): return "no va sincronizado con este video (comparado con \(con))"
            case .sinComprobar(let motivo): return "sincronía sin comprobar (\(motivo))"
            }
        }
    }

    // MARK: - Tiempos del .srt

    static let lineaDeTiempo = try! NSRegularExpression(
        pattern: "(\\d{1,2}):(\\d{2}):(\\d{2})[,.](\\d{1,3})\\s*-->\\s*(\\d{1,2}):(\\d{2}):(\\d{2})[,.](\\d{1,3})")

    /// Inicio y fin de cada línea, en segundos.
    public static func tiempos(_ texto: String) -> [(inicio: Double, fin: Double)] {
        let ns = texto as NSString
        return lineaDeTiempo.matches(in: texto, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            func n(_ i: Int) -> Double { Double(ns.substring(with: m.range(at: i))) ?? 0 }
            func milis(_ i: Int) -> Double {
                let s = ns.substring(with: m.range(at: i))
                return (Double(s.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0) / 1000
            }
            let inicio = n(1) * 3600 + n(2) * 60 + n(3) + milis(4)
            let fin = n(5) * 3600 + n(6) * 60 + n(7) + milis(8)
            return fin > inicio ? (inicio, fin) : nil
        }
    }

    /// Mueve todos los tiempos: `escala × t + desfase` (nunca por debajo de cero).
    public static func aplicar(_ ajuste: Ajuste, a texto: String) -> String {
        let ns = texto as NSString
        var salida = ""
        var desde = 0
        for m in lineaDeTiempo.matches(in: texto, range: NSRange(location: 0, length: ns.length)) {
            salida += ns.substring(with: NSRange(location: desde, length: m.range.location - desde))
            let mios = tiempos(ns.substring(with: m.range))
            if let t = mios.first {
                let inicio = max(0, ajuste.escala * t.inicio + ajuste.desfase)
                let fin = max(inicio + 0.1, ajuste.escala * t.fin + ajuste.desfase)
                salida += "\(formato(inicio)) --> \(formato(fin))"
            } else {
                salida += ns.substring(with: m.range)
            }
            desde = m.range.location + m.range.length
        }
        salida += ns.substring(from: desde)
        return salida
    }

    /// Sólo para pruebas: corre las líneas que empiezan después de `desde` (otro montaje).
    public static func aplicarDesde(_ desde: Double, desfase: Double, a texto: String) -> String {
        let bloques = texto.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        return bloques.map { bloque in
            guard let t = tiempos(bloque).first, t.inicio >= desde else { return bloque }
            return aplicar(Ajuste(escala: 1, desfase: desfase), a: bloque)
        }.joined(separator: "\n\n")
    }

    static func formato(_ segundos: Double) -> String {
        let total = Int((segundos * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", total / 3_600_000, total / 60_000 % 60, total / 1000 % 60, total % 1000)
    }

    // MARK: - Referencia

    /// Lo que seguro va con el video, ya convertido en señal.
    public struct Referencia: Sendable {
        public let descripcion: String
        /// Centrada (media cero) dentro de las ventanas; cero fuera.
        let señal: [Float]
        /// Los tramos donde hay datos. Con un subtítulo, la película en cuatro partes;
        /// con el audio, los tres tramos que se escucharon.
        let ventanas: [Range<Int>]
        let esAudio: Bool
        /// Con un subtítulo de referencia: dónde empieza y acaba cada línea, para afinar.
        let inicios: [Double]
        let finales: [Double]

        init(descripcion: String, cruda: [Float], ventanas: [Range<Int>], esAudio: Bool,
             inicios: [Double] = [], finales: [Double] = []) {
            self.descripcion = descripcion
            self.ventanas = ventanas
            self.esAudio = esAudio
            self.inicios = inicios.sorted()
            self.finales = finales.sorted()
            var señal = [Float](repeating: 0, count: cruda.count)
            for v in ventanas {
                let tramo = Array(cruda[v])
                let media = tramo.reduce(0, +) / Float(max(tramo.count, 1))
                for i in v { señal[i] = cruda[i] - media }
            }
            self.señal = señal
        }
    }

    /// Primero un subtítulo de texto del propio archivo; si no trae, el audio.
    public static func referencia(para video: URL) -> Referencia? {
        referenciaDeSubtitulo(video) ?? referenciaDeAudio(video)
    }

    public static func referenciaDeSubtitulo(_ video: URL) -> Referencia? {
        guard let pistas = try? Sondeo.pistas(de: video) else { return nil }
        // Completas antes que forzadas (que traen diez líneas) y que las de sordos (ruido extra).
        let candidatas = pistas.filter { $0.esTexto && !$0.forzada && !$0.descartable }
            .sorted { a, b in
                func n(_ p: Pista) -> Int { (p.idioma == "eng" ? 2 : 0) + (p.paraSordos ? 0 : 1) }
                return n(a) > n(b)
            }
        for pista in candidatas.prefix(2) {
            let temporal = FileManager.default.temporaryDirectory
                .appendingPathComponent("subfix-referencia-\(UUID().uuidString).srt")
            defer { try? FileManager.default.removeItem(at: temporal) }
            guard (try? Sondeo.extraer(pista: pista, de: video, a: temporal)) != nil,
                  let texto = try? TextoSRT.leer(temporal).texto else { continue }
            let cues = tiempos(texto)
            guard cues.count >= 80, let primera = cues.first?.inicio, let ultima = cues.map(\.fin).max() else { continue }
            let largo = Int((ultima + Double(busqueda) / hz + 60) * hz)
            let cruda = señal(cues, escala: 1, largo: largo)
            let a = Int(primera * hz), b = Int(ultima * hz)
            let cuarto = max((b - a) / 4, 1)
            let ventanas = (0..<4).map { i in (a + i * cuarto)..<(i == 3 ? b : a + (i + 1) * cuarto) }
            let nombres = ["eng": "inglés", "spa": "español", "por": "portugués", "fre": "francés",
                           "fra": "francés", "ita": "italiano", "ger": "alemán", "deu": "alemán"]
            let idioma = nombres[pista.idioma ?? ""].map { "en \($0) " } ?? ""
            return Referencia(descripcion: "el subtítulo \(idioma)que trae el video",
                              cruda: cruda, ventanas: ventanas, esAudio: false,
                              inicios: cues.map(\.inicio), finales: cues.map(\.fin))
        }
        return nil
    }

    // MARK: Audio

    private struct InfoDeAudio: Decodable {
        struct Flujo: Decodable { let channels: Int?; let channel_layout: String? }
        struct Formato: Decodable { let duration: String? }
        let streams: [Flujo]?
        let format: Formato?
    }

    public static func referenciaDeAudio(_ video: URL) -> Referencia? {
        guard let salida = try? Herramientas.correr("ffprobe", [
            "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=channels,channel_layout:format=duration", "-of", "json", video.path,
        ]), salida.codigo == 0,
              let info = try? JSONDecoder().decode(InfoDeAudio.self, from: Data(salida.texto.utf8)),
              let flujo = info.streams?.first,
              let duracion = Double(info.format?.duration ?? ""), duracion > 300 else { return nil }

        // La voz va en el canal central; en estéreo, mezclado. Y sólo la banda de la voz.
        let disposicion = flujo.channel_layout ?? ""
        let canales = flujo.channels ?? 2
        let conCentro = ["3.0", "4.0", "5.0", "5.1", "6.0", "6.1", "7.0", "7.1"].contains { disposicion.hasPrefix($0) }
        let mezcla = conCentro ? "pan=mono|c0=FC," : (canales >= 2 ? "pan=mono|c0=0.5*c0+0.5*c1," : "")
        let filtro = mezcla + "highpass=f=300,lowpass=f=3000"

        let largoVentana = duracion > 1800 ? 300.0 : min(180, duracion / 5)
        let inicios = [0.1, 0.35, 0.6, 0.85]
        let largo = Int((duracion + Double(busqueda) / hz + 60) * hz)
        var cruda = [Float](repeating: 0, count: largo)
        var ventanas: [Range<Int>] = []

        for fraccion in inicios {
            let inicio = (duracion * fraccion).rounded()
            let temporal = FileManager.default.temporaryDirectory
                .appendingPathComponent("subfix-audio-\(UUID().uuidString).raw")
            defer { try? FileManager.default.removeItem(at: temporal) }
            guard let r = try? Herramientas.correr("ffmpeg", [
                "-v", "error", "-nostdin", "-ss", String(format: "%.0f", inicio), "-t", String(format: "%.0f", largoVentana),
                "-i", video.path, "-map", "0:a:0", "-af", filtro, "-ar", "8000",
                "-c:a", "pcm_s16le", "-f", "s16le", "-y", temporal.path,
            ]), r.codigo == 0, let datos = try? Data(contentsOf: temporal), datos.count > 16000 else { continue }
            let habla = hablaDe(datos)
            let desde = Int(inicio * hz)
            let hasta = min(desde + habla.count, largo)
            guard hasta > desde else { continue }
            for i in desde..<hasta { cruda[i] = habla[i - desde] }
            ventanas.append(desde..<hasta)
        }
        guard ventanas.count >= 2 else { return nil }
        return Referencia(descripcion: "el audio de la película", cruda: cruda, ventanas: ventanas, esAudio: true)
    }

    /// De PCM 8 kHz mono a «cuánto se habla» en cada décima de segundo (0…1).
    /// Energía en tramos de 20 ms; se cuenta como voz lo que pasa del punto medio
    /// entre el ruido de fondo y lo más fuerte del tramo.
    static func hablaDe(_ pcm: Data) -> [Float] {
        let muestras: [Float] = pcm.withUnsafeBytes { crudo in
            let enteros = crudo.bindMemory(to: Int16.self)
            var f = [Float](repeating: 0, count: enteros.count)
            vDSP_vflt16(enteros.baseAddress!, 1, &f, 1, vDSP_Length(enteros.count))
            return f
        }
        let porTramo = 160
        let tramos = muestras.count / porTramo
        guard tramos > 50 else { return [] }
        var energia = [Float](repeating: 0, count: tramos)
        muestras.withUnsafeBufferPointer { p in
            for i in 0..<tramos {
                var cuadrado: Float = 0
                vDSP_measqv(p.baseAddress! + i * porTramo, 1, &cuadrado, vDSP_Length(porTramo))
                energia[i] = 10 * log10(cuadrado + 1)
            }
        }
        let ordenada = energia.sorted()
        let fondo = ordenada[Int(Double(tramos) * 0.2)]
        let tope = ordenada[Int(Double(tramos) * 0.97)]
        let umbral = fondo + 0.5 * (tope - fondo)
        let porDecima = 5
        return (0..<(tramos / porDecima)).map { d in
            var voz = 0
            for i in (d * porDecima)..<(d * porDecima + porDecima) where energia[i] > umbral { voz += 1 }
            return Float(voz) / Float(porDecima)
        }
    }

    // MARK: - Comparación

    static func señal(_ cues: [(inicio: Double, fin: Double)], escala: Double, largo: Int) -> [Float] {
        var s = [Float](repeating: 0, count: largo)
        for c in cues {
            let a = max(0, Int((c.inicio * escala * hz).rounded()))
            let b = min(largo, Int((c.fin * escala * hz).rounded()))
            if b > a { for i in a..<b { s[i] = 1 } }
        }
        return s
    }

    /// Para cada desplazamiento k en −K…K: Σ ref(t) · cand(t − k) dentro de `ventana`.
    static func correlaciones(_ ref: [Float], _ candPadded: [Float], K: Int, ventana: Range<Int>, rango: ClosedRange<Int>) -> [Float] {
        var salida = [Float](repeating: 0, count: rango.count)
        let n = vDSP_Length(ventana.count)
        ref.withUnsafeBufferPointer { r in
            candPadded.withUnsafeBufferPointer { c in
                for (j, k) in rango.enumerated() {
                    var suma: Float = 0
                    vDSP_dotpr(r.baseAddress! + ventana.lowerBound, 1,
                               c.baseAddress! + (ventana.lowerBound - k + K), 1, &suma, n)
                    salida[j] = suma
                }
            }
        }
        return salida
    }

    struct Pico { let k: Double; let valor: Float; let z: Float }

    /// El mejor desplazamiento (con medio paso de precisión) y cuánto sobresale del resto.
    static func pico(_ valores: [Float], rango: ClosedRange<Int>) -> Pico? {
        guard valores.count >= 3 else { return nil }
        var maximo: Float = 0, posicion: vDSP_Length = 0
        vDSP_maxvi(valores, 1, &maximo, &posicion, vDSP_Length(valores.count))
        var media: Float = 0, desviacion: Float = 0
        vDSP_normalize(valores, 1, nil, 1, &media, &desviacion, vDSP_Length(valores.count))
        let i = Int(posicion)
        var fino = Double(i)
        if i > 0, i < valores.count - 1 {
            let a = Double(valores[i - 1]), b = Double(valores[i]), c = Double(valores[i + 1])
            let curva = a - 2 * b + c
            if curva < 0 { fino += max(-0.5, min(0.5, 0.5 * (a - c) / curva)) }
        }
        return Pico(k: fino + Double(rango.lowerBound), valor: maximo,
                    z: desviacion > 0 ? (maximo - media) / desviacion : 0)
    }

    /// Lo que se mide de un candidato; `veredicto` lo traduce. Separado para poder calibrar.
    public struct Medida: CustomStringConvertible, Sendable {
        public let ajuste: Ajuste
        /// Cuánto sobresale el mejor desplazamiento (desviaciones típicas).
        public let confianza: Float
        /// Lo que cada tramo pide además del ajuste global (s); nil = tramo sin datos claros.
        public let residuos: [Double?]
        let zLocales: [Float]
        public var description: String {
            let r = residuos.map { $0.map { String(format: "%+.1f", $0) } ?? "·" }.joined(separator: " ")
            let z = zLocales.map { String(format: "%.1f", $0) }.joined(separator: " ")
            return String(format: "escala %.4f desfase %+.2f s confianza %.1f residuos [%@] z [%@]",
                          ajuste.escala, ajuste.desfase, confianza, r, z)
        }
    }

    public static func medir(_ texto: String, con ref: Referencia) -> Medida? {
        let cues = tiempos(texto)
        guard cues.count >= 30 else { return nil }
        let largo = ref.señal.count
        let K = busqueda
        let rango = -K...K
        var mejor: (escala: Double, pico: Pico, padded: [Float])?

        for escala in escalas {
            let padded = [Float](repeating: 0, count: K) + señal(cues, escala: escala, largo: largo) + [Float](repeating: 0, count: K)
            var total = [Float](repeating: 0, count: rango.count)
            for v in ref.ventanas {
                let parcial = correlaciones(ref.señal, padded, K: K, ventana: v, rango: rango)
                vDSP_vadd(total, 1, parcial, 1, &total, 1, vDSP_Length(total.count))
            }
            guard let p = pico(total, rango: rango) else { continue }
            // Sólo se cambia de velocidad si alinea claramente mejor que a velocidad normal.
            if let m = mejor, p.valor <= m.pico.valor * (escala == 1 ? 1 : 1.15) { continue }
            mejor = (escala, p, padded)
        }
        guard let mejor else { return nil }

        // Cada tramo por separado, cerca del ajuste global (±60 s).
        let centro = Int(mejor.pico.k.rounded())
        let local = max(-K, centro - 600)...min(K, centro + 600)
        var zLocales: [Float] = []
        let residuos: [Double?] = ref.ventanas.map { v in
            guard v.count > 600, let p = pico(correlaciones(ref.señal, mejor.padded, K: K, ventana: v, rango: local), rango: local)
            else { zLocales.append(0); return nil }
            zLocales.append(p.z)
            return p.z >= umbralLocal ? (p.k - mejor.pico.k) / hz : nil
        }
        // Con texto de referencia se afina con los bordes de cada línea. Ojo: cada sitio
        // pone el INICIO a su manera (el inglés de Spider-Man entra 0,5–0,9 s antes que el
        // español, y los dos van bien con el audio), pero el FINAL suele ser el mismo. Se
        // toma el valor más repetido de inicios o de finales, el que más se repita.
        var desfase = mejor.pico.k / hz
        if !ref.inicios.isEmpty {
            var mejorBorde: (cuenta: Int, valor: Double) = (0, 0)
            for (propios, ajenos) in [(cues.map(\.inicio), ref.inicios), (cues.map(\.fin), ref.finales)] {
                var cubetas: [Int: [Double]] = [:]
                for x in propios {
                    let t = mejor.escala * x + desfase
                    if let r = cercano(t, en: ajenos), abs(r - t) < 1 {
                        cubetas[Int(((r - t) * 10).rounded()), default: []].append(r - t)
                    }
                }
                if let (_, valores) = cubetas.max(by: { $0.value.count < $1.value.count }), valores.count > mejorBorde.cuenta {
                    mejorBorde = (valores.count, valores.reduce(0, +) / Double(valores.count))
                }
            }
            if mejorBorde.cuenta >= cues.count / 7 { desfase += mejorBorde.valor }
        }
        return Medida(ajuste: Ajuste(escala: mejor.escala, desfase: desfase),
                      confianza: mejor.pico.z, residuos: residuos, zLocales: zLocales)
    }

    /// El valor de `ordenados` más cercano a `t` (búsqueda binaria).
    static func cercano(_ t: Double, en ordenados: [Double]) -> Double? {
        guard !ordenados.isEmpty else { return nil }
        var bajo = 0, alto = ordenados.count - 1
        while bajo < alto {
            let medio = (bajo + alto) / 2
            if ordenados[medio] < t { bajo = medio + 1 } else { alto = medio }
        }
        if bajo > 0, abs(ordenados[bajo - 1] - t) < abs(ordenados[bajo] - t) { return ordenados[bajo - 1] }
        return ordenados[bajo]
    }

    /// De la medida a la decisión.
    public static func veredicto(_ medida: Medida?, con ref: Referencia) -> Veredicto {
        guard let medida else { return .sinComprobar("el subtítulo tiene muy pocas líneas") }
        let claros = medida.residuos.compactMap { $0 }
        // Dos tramos que piden cosas distintas: escenas de más o de menos, otro montaje.
        if claros.count >= 2, (claros.max()! - claros.min()!) > 1.0, medida.confianza >= 3.5 {
            return .desfasado(con: ref.descripcion)
        }
        // Con un subtítulo de referencia, uno correcto sobresale de 6 a 12; el de otra
        // película no pasa de 3. Con el audio, si no sale claro no se condena a nadie.
        if !ref.esAudio, medida.confianza < 4 { return .desfasado(con: ref.descripcion) }
        guard medida.confianza >= 5, claros.count >= 2 else {
            return .sinComprobar("no salió claro comparándolo con \(ref.descripcion)")
        }
        // Dos subtítulos buenos del mismo video pueden diferir medio segundo (Tony: el inglés
        // va 0,45 s detrás del español y el audio da la razón al español). El audio es más fino.
        let tolerancia = ref.esAudio ? 0.3 : 0.6
        if !medida.ajuste.cambiaVelocidad, abs(medida.ajuste.desfase) < tolerancia {
            return .sincronizado(con: ref.descripcion)
        }
        return .corregible(medida.ajuste, con: ref.descripcion)
    }

    public static func comprobar(_ texto: String, con ref: Referencia) -> Veredicto {
        veredicto(medir(texto, con: ref), con: ref)
    }

    /// Lo que usa el motor: prepara las referencias de un video sólo si hacen falta, una
    /// vez, y las reutiliza con cada candidato. Un corrimiento chico medido contra otro
    /// subtítulo se confirma con el audio antes de tocar nada.
    public final class Comprobador: @unchecked Sendable {
        public let video: URL
        private var texto: Referencia??
        private var audio: Referencia??
        private let cerrojo = NSLock()

        public init(video: URL) { self.video = video }

        private var deTexto: Referencia? {
            cerrojo.withLock {
                if texto == nil { texto = .some(Sincronia.referenciaDeSubtitulo(video)) }
                return texto!
            }
        }
        private var deAudio: Referencia? {
            cerrojo.withLock {
                if audio == nil { audio = .some(Sincronia.referenciaDeAudio(video)) }
                return audio!
            }
        }

        /// El video no trae subtítulo de texto ni se pudo leer su audio.
        public var sinReferencia: Bool { deTexto == nil && deAudio == nil }

        public func comprobar(_ srt: String) -> Veredicto {
            if let ref = deTexto {
                let v = Sincronia.comprobar(srt, con: ref)
                if case .corregible(let ajuste, _) = v, !ajuste.cambiaVelocidad, abs(ajuste.desfase) < 1.5,
                   let oido = deAudio {
                    let segunda = Sincronia.comprobar(srt, con: oido)
                    if case .sinComprobar = segunda { return v }
                    return segunda
                }
                return v
            }
            if let ref = deAudio { return Sincronia.comprobar(srt, con: ref) }
            return .sinComprobar("el video no trae subtítulos y no pude leer su audio")
        }
    }

    // MARK: - Huella

    /// Para reconocer un subtítulo ya rechazado aunque se baje de otro sitio: sus
    /// primeras palabras y sus primeros tiempos. Otro con el mismo texto pero
    /// re-sincronizado tiene otra huella (justo el que se quiere encontrar).
    public static func huella(_ texto: String) -> String {
        let tiempos = tiempos(texto).prefix(25).map { String(Int($0.inicio)) }.joined(separator: ",")
        let palabras = texto.components(separatedBy: "\n")
            .filter { !$0.contains("-->") && Int($0.trimmingCharacters(in: .whitespaces)) == nil }
            .joined(separator: " ").lowercased()
            .unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return String(String.UnicodeScalarView(palabras.prefix(400))) + "|" + tiempos
    }
}
