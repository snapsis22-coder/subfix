import Foundation

/// Mandar una película vieja a la Papelera junto con sus subtítulos sueltos.
/// Solo Papelera (se puede recuperar con «Devolver»); nunca se borra nada para siempre.
public enum Papelera {

    /// Los subtítulos que acompañan al video en su carpeta: «Peli.srt», «Peli.es.srt»,
    /// «Peli.forced.srt», «Peli.ass»… y las copias que deja SubFix («Peli.srt.anterior»,
    /// «Peli.srt.anterior2»). No entra «Peli (SubFix).srt» (después del nombre viene un
    /// espacio, no un punto) ni los de otro video cuyo nombre empiece igual
    /// («Peli.Extended.mkv» se queda con «Peli.Extended.srt»).
    public static func acompañantes(de video: URL) -> [URL] {
        let carpeta = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent
        guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path) else { return [] }

        let otrosVideos = nombres
            .filter { Motor.extensionesDeVideo.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { ($0 as NSString).deletingPathExtension }
            .filter { $0 != base && $0.hasPrefix(base + ".") }

        return nombres.filter { nombre in
            guard nombre.hasPrefix(base + "."), nombre != video.lastPathComponent else { return false }
            guard esSubtitulo(nombre) else { return false }
            return !otrosVideos.contains { nombre.hasPrefix($0 + ".") }
        }
        .sorted()
        .map { carpeta.appendingPathComponent($0) }
    }

    /// El MKV que SubFix creó a partir de este video, si está al lado:
    /// «Peli (SubFix).mkv», «Peli (SubFix 2).mkv»… (no vacío).
    public static func versionDeSubFix(de video: URL) -> URL? {
        let carpeta = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent
        guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path) else { return nil }
        return nombres.sorted()
            .filter { $0 != video.lastPathComponent && $0.hasPrefix(base + " (SubFix") && $0.lowercased().hasSuffix(".mkv") }
            .map { carpeta.appendingPathComponent($0) }
            .first { ((try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0 }
    }

    /// «x.srt», «x.ass»… o una copia apartada «x.srt.anterior», «x.srt.anterior2».
    static func esSubtitulo(_ nombre: String) -> Bool {
        let n = nombre.lowercased()
        if Motor.extensionesDeSubtitulo.contains((n as NSString).pathExtension) { return true }
        return n.range(of: #"\.(srt|ass|ssa|vtt)\.anterior\d*$"#, options: .regularExpression) != nil
    }

    /// La Papelera de macOS; en las pruebas se cambia por una carpeta cualquiera.
    public static let alaPapeleraDeMacOS: (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Manda el video y sus subtítulos a la Papelera y devuelve lo que se fue.
    /// Si el video no se puede mover, no se toca nada más.
    @discardableResult
    public static func enviar(_ video: URL,
                              mover: (URL) throws -> Void = alaPapeleraDeMacOS) throws -> [URL] {
        let subtitulos = acompañantes(de: video)
        do { try mover(video) } catch {
            throw ErrorDeSubFix.noSePudoMover("\(video.lastPathComponent): \(error.localizedDescription)")
        }
        var enviados = [video], fallidos: [String] = []
        for srt in subtitulos {
            do { try mover(srt); enviados.append(srt) } catch { fallidos.append(srt.lastPathComponent) }
        }
        if !fallidos.isEmpty {
            throw ErrorDeSubFix.noSePudoMover("el video sí se fue, pero quedaron: \(fallidos.joined(separator: ", "))")
        }
        return enviados
    }
}
