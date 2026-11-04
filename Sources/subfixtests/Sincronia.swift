import Foundation
import SubFixKit
import SubFixUI

/// La comprobación de sincronía con subtítulos inventados: una «película» que sólo
/// trae una pista en inglés, y candidatos en español buenos, corridos, de 25 fps,
/// de otro montaje y de otra película. (Contra películas reales: `swift run subfixsync`.)
func pruebasDeSincronia(en temporal: URL) async {
    print("\n▸ Sincronía de lo bajado")

    // Tiempos al azar pero siempre los mismos (generador congruencial).
    func tiempos(semilla: UInt64, cuantas: Int = 320) -> [(Double, Double)] {
        var estado = semilla, t = 20.0, salida: [(Double, Double)] = []
        func azar() -> Double { estado = estado &* 6364136223846793005 &+ 1442695040888963407; return Double(estado >> 33) / Double(1 << 31) }
        for _ in 0..<cuantas {
            t += 0.3 + 5 * azar() * azar()
            let dura = 1 + 3 * azar()
            salida.append((t, t + dura))
            t += dura
        }
        return salida
    }
    func srt(_ tiempos: [(Double, Double)], frase: String) -> String {
        tiempos.enumerated().map { i, c in
            "\(i + 1)\n\(formato(c.0)) --> \(formato(c.1))\n\(frase) \(i)\n"
        }.joined(separator: "\n")
    }
    func formato(_ s: Double) -> String {
        let ms = Int((s * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    let carpeta = temporal.appendingPathComponent("sincronia", isDirectory: true)
    try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    let buenos = tiempos(semilla: 7)
    let ingles = carpeta.appendingPathComponent("ingles.srt")
    try? srt(buenos, frase: "Are you guys hungry? I told you so").write(to: ingles, atomically: true, encoding: .utf8)
    // La película: un MKV con sólo la pista en inglés (lo arma el ffmpeg propio).
    let video = carpeta.appendingPathComponent("Pelicula.Inventada.2026.WEB-DL.mkv")
    _ = try? Herramientas.correr("ffmpeg", ["-nostdin", "-v", "error", "-y", "-i", ingles.path,
                                            "-map", "0", "-c:s", "srt", "-metadata:s:s:0", "language=eng", video.path])

    let latino = "¿Tienen hambre ustedes? Se los dije, está bien"
    let bueno = srt(buenos, frase: latino)
    let comprobador = Sincronia.Comprobador(video: video)

    probar("tiempos del .srt: se leen y se mueven sin tocar el texto") {
        let movido = Sincronia.aplicar(.init(escala: 1, desfase: 2.5), a: "1\n00:00:01,000 --> 00:00:02,5\nHola\n")
        return movido == "1\n00:00:03,500 --> 00:00:05,000\nHola\n"
            && Sincronia.tiempos("00:01:02,003 --> 00:01:03,1").first.map { $0.inicio == 62.003 && $0.fin == 63.1 } == true
    }

    probar("sincronía: el que va con la pista del video sale «sincronizado»") {
        if case .sincronizado = comprobador.comprobar(bueno) { return true }
        print("       salió: \(comprobador.comprobar(bueno))")
        return false
    }

    probar("sincronía: corrido 3 s se detecta y se puede corregir") {
        let corrido = Sincronia.aplicar(.init(escala: 1, desfase: 3), a: bueno)
        guard case .corregible(let ajuste, _) = comprobador.comprobar(corrido) else { return false }
        return abs(ajuste.desfase + 3) < 0.15 && !ajuste.cambiaVelocidad
    }

    probar("sincronía: hecho para 25 fps se detecta como otra velocidad") {
        let pal = Sincronia.aplicar(.init(escala: 23.976 / 25, desfase: 0), a: bueno)
        guard case .corregible(let ajuste, _) = comprobador.comprobar(pal) else { return false }
        return abs(ajuste.escala - 25 / 23.976) < 0.001
    }

    probar("sincronía: otro montaje (la 2ª mitad corrida 5 s) se rechaza") {
        let mitad = (buenos.last?.1 ?? 0) / 2
        guard case .desfasado = comprobador.comprobar(Sincronia.aplicarDesde(mitad, desfase: 5, a: bueno)) else { return false }
        return true
    }

    probar("sincronía: el de otra película se rechaza") {
        guard case .desfasado = comprobador.comprobar(srt(tiempos(semilla: 99), frase: latino)) else { return false }
        return true
    }

    // Un paquete de Subdivx con dos versiones: la corrida primero. Se instala la buena.
    let corrida = carpeta.appendingPathComponent("Pelicula.Inventada.2026.BluRay.srt")
    let sincronizada = carpeta.appendingPathComponent("Pelicula.Inventada.2026.WEB-DL.srt")
    try? Sincronia.aplicarDesde((buenos.last?.1 ?? 0) / 2, desfase: 6, a: bueno).write(to: corrida, atomically: true, encoding: .utf8)
    try? bueno.write(to: sincronizada, atomically: true, encoding: .utf8)

    probar("de un paquete con dos versiones se instala la que va sincronizada") {
        guard case .listo(let origen, _, _, _, _, _) = Motor.adoptarComprobando([corrida, sincronizada], para: video,
                                                                             preferirLatino: true) else { return false }
        return origen.contains("WEB-DL") && origen.contains("sincronía comprobada")
    }

    probar("si ninguno va sincronizado, no se instala nada") {
        let otra = carpeta.appendingPathComponent("Otra.mkv")
        try? FileManager.default.copyItem(at: video, to: otra)
        guard case .desfasado = Motor.adoptarComprobando([corrida], para: otra, preferirLatino: true) else { return false }
        return !FileManager.default.fileExists(atPath: Motor.destinoSRT(de: otra).path)
    }

    probar("corrido 2 s: se instala con los tiempos ya corregidos") {
        let otra = carpeta.appendingPathComponent("Corregida.mkv")
        try? FileManager.default.copyItem(at: video, to: otra)
        let movido = carpeta.appendingPathComponent("movido.srt")
        try? Sincronia.aplicar(.init(escala: 1, desfase: 2), a: bueno).write(to: movido, atomically: true, encoding: .utf8)
        guard case .listo = Motor.adoptarComprobando([movido], para: otra, preferirLatino: true),
              let puesto = try? TextoSRT.leer(Motor.destinoSRT(de: otra)).texto,
              let primera = Sincronia.tiempos(puesto).first else { return false }
        return abs(primera.inicio - buenos[0].0) < 0.15
    }

    probar("Reprocesar: el subtítulo rechazado no se vuelve a elegir aunque llegue crudo") {
        let puesto = (try? TextoSRT.leer(Motor.destinoSRT(de: video)).texto) ?? ""
        let rechazado: Set<String> = [Motor.huella(puesto)]
        guard case .falló = Motor.adoptarComprobando([sincronizada], para: video, preferirLatino: true,
                                                     descartados: rechazado) else { return false }
        return !puesto.isEmpty
    }

    await probarEsperando("Reprocesar en la lista: aparta el que tenía sólo si aparece otro") {
        let peli = carpeta.appendingPathComponent("Reprocesada.2026.mkv")
        try? FileManager.default.copyItem(at: video, to: peli)
        try? TextoSRT.escribirParaElTV(bueno, en: Motor.destinoSRT(de: peli))
        let c = await MainActor.run { Cola() }
        await MainActor.run { c.usarRed = false; c.extraerDelArchivo = false; c.agregar([peli]) }
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if await MainActor.run(body: { !c.pendientes.isEmpty }) { break }
        }
        guard let id = await MainActor.run(body: { c.filas.first?.id }) else { return false }
        await MainActor.run { c.reprocesar(id) }
        for _ in 0..<80 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if await MainActor.run(body: { !c.trabajando }) { break }
        }
        // Sin internet ni pista que extraer no aparece otro: el de antes sigue puesto, y se dice.
        let detalle = await MainActor.run { c.filas.first?.detalle ?? "" }
        let sigue = FileManager.default.fileExists(atPath: Motor.destinoSRT(de: peli).path)
        if !detalle.contains("sigue puesto") { print("       salió: \(detalle)") }
        return sigue && detalle.contains("sigue puesto")
    }
}
