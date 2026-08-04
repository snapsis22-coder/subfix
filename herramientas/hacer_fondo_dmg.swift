#!/usr/bin/env swift
// Dibuja el fondo de la ventana del DMG. Mismo criterio que el icono: por
// código, para poder retocarlo cambiando números.
//
//     swift herramientas/hacer_fondo_dmg.swift              genera el fondo elegido
//     swift herramientas/hacer_fondo_dmg.swift --variantes  lámina para comparar
//     swift herramientas/hacer_fondo_dmg.swift --fondo 3    genera otro de la lista
//
// ⚠ El icono de la app es grafito oscuro. Un fondo grafito lo hace desaparecer:
// el pie del icono (0.13,0.15,0.18) era idéntico al pie del fondo anterior. El
// fondo tiene que separarse del icono en CLARIDAD, no sólo en tono.

import AppKit

let ancho = 660.0, alto = 563.0          // el tamaño de ventana que fija build_dmg.sh
let posApp = CGPoint(x: 165, y: 245)     // posiciones reales de los iconos, para la lámina
let posCarpeta = CGPoint(x: 495, y: 245)
let ladoIcono = 108.0

struct Fondo {
    let nombre: String
    let arriba: (Double, Double, Double)
    let abajo: (Double, Double, Double)
    /// El icono es oscuro: sobre fondo claro el texto tiene que ser oscuro también.
    let textoOscuro: Bool
}

let fondos: [Fondo] = [
    Fondo(nombre: "Gris claro (el de Calculadora+ y TRM Fixer)",
          arriba: (0.66, 0.66, 0.68), abajo: (0.78, 0.78, 0.80), textoOscuro: true),
    Fondo(nombre: "Niebla fría",
          arriba: (0.88, 0.89, 0.91), abajo: (0.74, 0.76, 0.80), textoOscuro: true),
    Fondo(nombre: "Azul noche profundo",
          arriba: (0.10, 0.12, 0.19), abajo: (0.03, 0.04, 0.07), textoOscuro: false),
    Fondo(nombre: "Índigo de sala de cine",
          arriba: (0.24, 0.21, 0.46), abajo: (0.09, 0.08, 0.20), textoOscuro: false),
]

// El elegido. Se cambia aquí después de mirar la lámina de variantes.
let elegido = 0

let espacio = CGColorSpaceCreateDeviceRGB()

func color(_ r: Double, _ v: Double, _ a: Double, _ alfa: Double = 1) -> CGColor {
    CGColor(red: r, green: v, blue: a, alpha: alfa)
}

/// Pinta el degradado, la flecha y los textos. Devuelve la imagen lista.
func pintar(_ fondo: Fondo) -> NSImage? {
    guard let ctx = CGContext(data: nil, width: Int(ancho * 2), height: Int(alto * 2),
                              bitsPerComponent: 8, bytesPerRow: 0, space: espacio,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    ctx.scaleBy(x: 2, y: 2)              // @2x, que es como lo ve una pantalla Retina

    ctx.drawLinearGradient(CGGradient(colorsSpace: espacio,
                                      colors: [color(fondo.arriba.0, fondo.arriba.1, fondo.arriba.2),
                                               color(fondo.abajo.0, fondo.abajo.1, fondo.abajo.2)] as CFArray,
                                      locations: [0, 1])!,
                           start: CGPoint(x: 0, y: alto), end: CGPoint(x: 0, y: 0), options: [])

    // Flecha de «arrastra la app a Applications», entre los dos iconos.
    let tinta = fondo.textoOscuro ? 0.0 : 1.0
    ctx.setStrokeColor(color(tinta, tinta, tinta, fondo.textoOscuro ? 0.35 : 0.28))
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    let y = alto - 245.0                 // a la altura de los iconos
    ctx.move(to: CGPoint(x: 268, y: y))
    ctx.addLine(to: CGPoint(x: 392, y: y))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 376, y: y + 13))
    ctx.addLine(to: CGPoint(x: 393, y: y))
    ctx.addLine(to: CGPoint(x: 376, y: y - 13))
    ctx.strokePath()

    guard let imagen = ctx.makeImage() else { return nil }
    let lienzo = NSImage(size: NSSize(width: ancho, height: alto))
    lienzo.lockFocus()
    NSGraphicsContext.current?.cgContext.draw(imagen, in: CGRect(x: 0, y: 0, width: ancho, height: alto))

    func escribir(_ texto: String, _ tamaño: Double, _ peso: NSFont.Weight,
                  _ alfa: Double, _ desdeArriba: Double) {
        let atributos: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: tamaño, weight: peso),
            .foregroundColor: NSColor(white: fondo.textoOscuro ? 0.12 : 1, alpha: alfa),
        ]
        let cadena = texto as NSString
        let medida = cadena.size(withAttributes: atributos)
        cadena.draw(at: NSPoint(x: (ancho - medida.width) / 2, y: alto - desdeArriba - medida.height),
                    withAttributes: atributos)
    }

    escribir("SubFix", 30, .semibold, 0.95, 48)
    escribir("Subtítulos listos para tu televisor", 14, .regular, fondo.textoOscuro ? 0.7 : 0.6, 88)
    lienzo.unlockFocus()
    return lienzo
}

func guardar(_ imagen: NSImage, en ruta: URL) {
    try? FileManager.default.createDirectory(at: ruta.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    if let tiff = imagen.tiffRepresentation, let mapa = NSBitmapImageRep(data: tiff),
       let png = mapa.representation(using: .png, properties: [:]) {
        try? png.write(to: ruta)
        print("✓ \(ruta.path)")
    }
}

let aquí = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let argumentos = CommandLine.arguments

// --------------------------------------------------------------- variantes

if argumentos.contains("--variantes") {
    // Con los iconos encima y en su sitio real: el problema era justamente que el
    // icono se perdía contra el fondo, así que hay que verlos juntos.
    let iconoApp = NSImage(contentsOf: aquí.appendingPathComponent("Resources/AppIcon.icns"))
    let iconoCarpeta = NSWorkspace.shared.icon(forFile: "/Applications")

    let columnas = 2.0
    let filas = ceil(Double(fondos.count) / columnas)
    let margen = 24.0, pie = 30.0
    let lámina = NSImage(size: NSSize(width: columnas * ancho + margen * (columnas + 1),
                                      height: filas * (alto + pie) + margen * (filas + 1)))
    lámina.lockFocus()
    NSColor(white: 0.35, alpha: 1).setFill()
    NSRect(origin: .zero, size: lámina.size).fill()

    for (indice, fondo) in fondos.enumerated() {
        guard let imagen = pintar(fondo) else { continue }
        let columna = Double(indice % Int(columnas))
        let fila = Double(indice / Int(columnas))
        let x = margen + columna * (ancho + margen)
        let y = lámina.size.height - margen - (fila + 1) * (alto + pie) - fila * margen + pie

        imagen.draw(in: NSRect(x: x, y: y, width: ancho, height: alto))
        // Los iconos van con el origen arriba-izquierda, como los cuenta el Finder.
        iconoApp?.draw(in: NSRect(x: x + posApp.x - ladoIcono / 2,
                                  y: y + alto - posApp.y - ladoIcono / 2,
                                  width: ladoIcono, height: ladoIcono))
        iconoCarpeta.draw(in: NSRect(x: x + posCarpeta.x - ladoIcono / 2,
                                     y: y + alto - posCarpeta.y - ladoIcono / 2,
                                     width: ladoIcono, height: ladoIcono))

        let texto = "\(indice + 1). \(fondo.nombre)" as NSString
        texto.draw(at: NSPoint(x: x, y: y - 24), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
    }
    lámina.unlockFocus()
    guardar(lámina, en: aquí.appendingPathComponent("dmg_assets/variantes_fondo.png"))
    exit(0)
}

// --------------------------------------------------------------- generar

var cuál = elegido
if let i = argumentos.firstIndex(of: "--fondo"), argumentos.count > i + 1,
   let n = Int(argumentos[i + 1]), n >= 1, n <= fondos.count {
    cuál = n - 1
}
print("▸ Fondo: \(fondos[cuál].nombre)")
if let imagen = pintar(fondos[cuál]) {
    guardar(imagen, en: aquí.appendingPathComponent("dmg_assets/background.png"))
}
