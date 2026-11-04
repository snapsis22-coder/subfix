import Foundation
import SubFixKit

// Calibrar la comprobación de sincronía con películas de verdad:
//
//     swift run subfixsync <video> <subtítulo.srt> [--audio|--texto]
//
// Mide el .srt tal cual y tres versiones estropeadas a propósito (corrido 2,5 s,
// hecho para 25 fps y con la segunda mitad corrida), contra la referencia elegida.
let args = CommandLine.arguments.dropFirst()
guard args.count >= 2 else {
    print("uso: subfixsync <video> <subtítulo.srt> [--audio|--texto]")
    exit(2)
}
let video = URL(fileURLWithPath: args[args.startIndex])
let srt = URL(fileURLWithPath: args[args.startIndex + 1])
let modo = args.dropFirst(2).first

let texto = try TextoSRT.leer(srt).texto
let inicio = Date()
let ref: Sincronia.Referencia? = switch modo {
case "--audio": Sincronia.referenciaDeAudio(video)
case "--texto": Sincronia.referenciaDeSubtitulo(video)
default: Sincronia.referencia(para: video)
}
guard let ref else { print("sin referencia"); exit(1) }
print("referencia: \(ref.descripcion) (\(String(format: "%.1f", Date().timeIntervalSince(inicio))) s)")

let mitad = (Sincronia.tiempos(texto).last?.fin ?? 0) / 2
let casos: [(String, String)] = [
    ("tal cual", texto),
    ("corrido +2,5 s", Sincronia.aplicar(.init(escala: 1, desfase: 2.5), a: texto)),
    ("corrido −0,8 s", Sincronia.aplicar(.init(escala: 1, desfase: -0.8), a: texto)),
    ("hecho para 25 fps", Sincronia.aplicar(.init(escala: 23.976 / 25, desfase: 0), a: texto)),
    ("2ª mitad +4 s", Sincronia.aplicarDesde(mitad, desfase: 4, a: texto)),
]
for (nombre, t) in casos {
    let antes = Date()
    let medida = Sincronia.medir(t, con: ref)
    let v = Sincronia.veredicto(medida, con: ref)
    print("\(nombre.padding(toLength: 18, withPad: " ", startingAt: 0)) \(medida.map(String.init(describing:)) ?? "—")"
          + "  → \(v.resumen)  (\(String(format: "%.2f", Date().timeIntervalSince(antes))) s)")
}
