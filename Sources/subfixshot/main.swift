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
func retratar<V: View>(_ vista: V, _ nombre: String, en carpeta: URL,
                       ancho: CGFloat = 1040, alto: CGFloat = 720, oscuro: Bool = false) {
    NSApp.appearance = NSAppearance(named: oscuro ? .darkAqua : .aqua)
    let renderizador = ImageRenderer(content:
        vista.frame(width: ancho, height: alto)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, oscuro ? .dark : .light)
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

    let pistas = ColaDePistas()
    retratar(Retratos.pistas(pistas), "3-pistas-vacia", en: salida)
    if !peliculas.isEmpty {
        pistas.agregar(Array(peliculas))
        RunLoop.main.run(until: Date().addingTimeInterval(4))
        retratar(Retratos.pistas(pistas), "3-pistas", en: salida)
    }
    retratar(Retratos.barras(), "4-barras", en: salida, ancho: 640, alto: 300)
    retratar(Retratos.tiraDelSello(), "6-sello", en: salida, ancho: 640, alto: 150)
    retratar(Retratos.filasDeEjemplo(), "7-filas", en: salida, ancho: 1000, alto: 440)
    retratar(Retratos.filasDeEjemplo(), "7-filas-oscuro", en: salida, ancho: 1000, alto: 440, oscuro: true)
    retratar(Retratos.organizar(vacia: true), "8-organizar-vacia", en: salida)
    retratar(Retratos.organizar(), "9-organizar", en: salida)
    retratar(Retratos.organizar(), "10-organizar-oscuro", en: salida, oscuro: true)
    retratar(Retratos.editorDeNombre(), "11-editor", en: salida, ancho: 320, alto: 330)
    retratar(Retratos.opciones(cola), "12-opciones", en: salida, ancho: 400, alto: 300)
    retratar(Retratos.peliculas(Cola()), "13-vacia-oscuro", en: salida, oscuro: true)
}
