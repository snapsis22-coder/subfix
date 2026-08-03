import AppKit
import SubFixKit
import SubFixUI
import SwiftUI

/// Renderiza la interfaz a PNG sin abrir ventana, para poder revisarla sin
/// depender del permiso de grabación de pantalla del sistema.
///
///     swift run subfixshot <carpeta-de-salida> [películas…]
///
/// ⚠ Sólo sirve para vistas de SwiftUI puro. `List` y `Form` están hechas sobre
/// AppKit y ImageRenderer no las sabe pintar fuera de pantalla: salen en blanco
/// o con el símbolo de prohibido. Para revisar esas pantallas hay que abrir la
/// app de verdad.

@MainActor
func retratar<V: View>(_ vista: V, _ nombre: String, en carpeta: URL, alto: CGFloat = 470) {
    let renderizador = ImageRenderer(content:
        vista.frame(width: 640, height: alto).background(Color(nsColor: .windowBackgroundColor))
    )
    renderizador.scale = 2
    guard let imagen = renderizador.nsImage,
          let tiff = imagen.tiffRepresentation,
          let mapa = NSBitmapImageRep(data: tiff),
          let png = mapa.representation(using: .png, properties: [:]) else {
        print("  ✗ no se pudo renderizar \(nombre)")
        return
    }
    let destino = carpeta.appendingPathComponent("\(nombre).png")
    try? png.write(to: destino)
    print("  ✓ \(destino.path)")
}

let argumentos = Array(CommandLine.arguments.dropFirst())
guard let salida = argumentos.first.map({ URL(fileURLWithPath: $0) }) else {
    print("uso: subfixshot <carpeta-de-salida> [películas…]")
    exit(1)
}
try? FileManager.default.createDirectory(at: salida, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

MainActor.assumeIsolated {
    let cola = Cola()
    retratar(Retratos.peliculas(cola), "1-vacia", en: salida)

    let peliculas = argumentos.dropFirst().map { URL(fileURLWithPath: $0) }
    if !peliculas.isEmpty {
        cola.agregar(Array(peliculas))
        // El diagnóstico corre en segundo plano: darle tiempo antes del retrato.
        RunLoop.main.run(until: Date().addingTimeInterval(6))
        retratar(Retratos.peliculas(cola), "2-con-peliculas", en: salida)
    }

    retratar(Retratos.vigilancia(Vigilante()), "3-vigilancia", en: salida)
}
