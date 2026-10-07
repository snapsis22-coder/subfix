import Foundation

/// Reempaqueta una película en un .mkv nuevo sin recodificar nada: se queda con
/// el video, los audios elegidos, los capítulos y los adjuntos, descarta todos
/// los subtítulos del original y mete el .srt que SubFix dejó listo.
///
/// Es lo que antes se hacía a mano en MKVToolNix, con la ventaja de que el .srt
/// ya va en UTF-8 y no hay que adivinar su codificación. El original no se toca.
public enum Remux {

    /// «Película.mkv» → «Película (SubFix).mkv», en la misma carpeta.
    public static func destino(para video: URL) -> URL {
        let base = video.deletingPathExtension().lastPathComponent
        return video.deletingLastPathComponent().appendingPathComponent("\(base) (SubFix).mkv")
    }

    /// Los argumentos de ffmpeg; aparte para poder probarlos sin ejecutar nada.
    public static func argumentos(video: URL, subtitulo: URL, audios: [Int], salida: URL) -> [String] {
        var args = ["-nostdin", "-v", "error", "-y", "-i", video.path, "-i", subtitulo.path, "-map", "0:v"]
        for indice in audios { args += ["-map", "0:\(indice)"] }
        args += ["-map", "1:0", "-map_chapters", "0", "-map", "0:t?", "-c", "copy",
                 "-metadata:s:s:0", "language=spa", "-metadata:s:s:0", "title=Español",
                 "-disposition:s:0", "default"]
        // El primer audio se reproduce por defecto; el resto, no.
        for (posicion, _) in audios.enumerated() {
            args += ["-disposition:a:\(posicion)", posicion == 0 ? "default" : "0"]
        }
        return args + ["-f", "matroska", salida.path]
    }

    /// Crea el .mkv junto al original y devuelve su ruta. Nunca pisa un archivo.
    @discardableResult
    public static func hacer(video: URL, subtitulo: URL, audios: [Int]) throws -> URL {
        let final = destino(para: video)
        guard !FileManager.default.fileExists(atPath: final.path) else {
            throw ErrorDeSubFix.fallóElRemux("ya existe «\(final.lastPathComponent)» junto a la película")
        }
        guard !audios.isEmpty else { throw ErrorDeSubFix.fallóElRemux("no quedó ningún audio marcado") }

        // Se escribe con otro nombre y sólo al terminar bien se pone el definitivo:
        // un corte a medias no deja un .mkv truncado que parezca bueno.
        let parcial = final.deletingLastPathComponent()
            .appendingPathComponent(".\(final.deletingPathExtension().lastPathComponent).parcial")
        let salida = try Herramientas.correr("ffmpeg", argumentos(video: video, subtitulo: subtitulo,
                                                                  audios: audios, salida: parcial))
        let tamaño = ((try? FileManager.default.attributesOfItem(atPath: parcial.path))?[.size] as? Int) ?? 0
        guard salida.codigo == 0, tamaño > 0 else {
            try? FileManager.default.removeItem(at: parcial)   // sólo el parcial que acabo de crear
            throw ErrorDeSubFix.fallóElRemux(salida.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try FileManager.default.moveItem(at: parcial, to: final)
        return final
    }
}
