import Foundation

/// Localiza ffmpeg y ffprobe y los ejecuta.
///
/// La app **lleva los suyos dentro** (`Contents/Resources/bin`): una compilación
/// mínima y estática, sólo con lo de subtítulos, sin dependencias fuera de
/// /usr/lib. Así funciona en cualquier Mac aunque no tenga Homebrew. Si por lo
/// que sea faltaran, se recurre a los del sistema.
public enum Herramientas {

    /// Homebrew según el chip, más las del sistema para `mount` y `dot_clean`.
    static let carpetas = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/sbin", "/usr/sbin"]

    /// Los binarios que viajan dentro del bundle, cuando se corre como app.
    static var carpetaDelBundle: String? {
        guard let recursos = Bundle.main.resourcePath else { return nil }
        let bin = recursos + "/bin"
        return FileManager.default.fileExists(atPath: bin) ? bin : nil
    }

    public static func ruta(de orden: String) -> String? {
        var candidatas: [String] = []
        if let propia = carpetaDelBundle { candidatas.append(propia + "/" + orden) }
        candidatas += carpetas.map { $0 + "/" + orden }

        return candidatas.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Para poder decir en la interfaz de dónde salió el ffmpeg que se está usando.
    public static var ffmpegEsPropio: Bool {
        guard let propia = carpetaDelBundle, let usada = ruta(de: "ffmpeg") else { return false }
        return usada.hasPrefix(propia)
    }

    public static var faltantes: [String] {
        ["ffmpeg", "ffprobe"].filter { ruta(de: $0) == nil }
    }

    public struct Salida {
        public let codigo: Int32
        public let texto: String
        public let error: String
    }

    /// Ejecuta una orden y espera. Se llama siempre fuera del hilo principal.
    @discardableResult
    public static func correr(_ orden: String, _ argumentos: [String]) throws -> Salida {
        guard let ejecutable = ruta(de: orden) else {
            throw ErrorDeSubFix.faltaHerramienta(orden)
        }
        let proceso = Process()
        proceso.executableURL = URL(fileURLWithPath: ejecutable)
        proceso.arguments = argumentos

        let tuboSalida = Pipe(), tuboError = Pipe()
        proceso.standardOutput = tuboSalida
        proceso.standardError = tuboError
        try proceso.run()

        // Leer antes de esperar: con salidas grandes (un .srt entero) el tubo se
        // llena y el proceso se queda bloqueado escribiendo para siempre.
        let datos = tuboSalida.fileHandleForReading.readDataToEndOfFile()
        let errores = tuboError.fileHandleForReading.readDataToEndOfFile()
        proceso.waitUntilExit()

        return Salida(codigo: proceso.terminationStatus,
                      texto: String(data: datos, encoding: .utf8) ?? "",
                      error: String(data: errores, encoding: .utf8) ?? "")
    }
}

public enum ErrorDeSubFix: LocalizedError {
    case faltaHerramienta(String)
    case noSePudoSondear(String)
    case fallóLaExtracción(String)

    public var errorDescription: String? {
        switch self {
        case .faltaHerramienta(let cual):
            return "Falta \(cual). Instálalo con: brew install ffmpeg"
        case .noSePudoSondear(let detalle):
            return "No se pudo leer el archivo: \(detalle)"
        case .fallóLaExtracción(let detalle):
            return "La extracción falló: \(detalle)"
        }
    }
}
