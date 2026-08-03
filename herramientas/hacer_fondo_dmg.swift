#!/usr/bin/env swift
// Dibuja el fondo de la ventana del DMG. Mismo criterio que el icono: por
// código, para poder retocarlo cambiando números.
//
//     swift herramientas/hacer_fondo_dmg.swift

import AppKit

let ancho = 660.0, alto = 563.0          // el tamaño de ventana que fija build_dmg.sh

let espacio = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(ancho * 2), height: Int(alto * 2),
                          bitsPerComponent: 8, bytesPerRow: 0, space: espacio,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no se pudo crear el lienzo")
}
ctx.scaleBy(x: 2, y: 2)                  // @2x, que es como lo ve una pantalla Retina

func color(_ r: Double, _ v: Double, _ a: Double, _ alfa: Double = 1) -> CGColor {
    CGColor(red: r, green: v, blue: a, alpha: alfa)
}

// Fondo: el mismo grafito del icono, en vertical.
ctx.drawLinearGradient(CGGradient(colorsSpace: espacio,
                                  colors: [color(0.24, 0.26, 0.30),
                                           color(0.13, 0.14, 0.17)] as CFArray,
                                  locations: [0, 1])!,
                       start: CGPoint(x: 0, y: alto), end: CGPoint(x: 0, y: 0), options: [])

// Flecha de «arrastra la app a Applications», entre los dos iconos.
ctx.setStrokeColor(color(1, 1, 1, 0.28))
ctx.setLineWidth(3)
ctx.setLineCap(.round)
let y = alto - 245.0                     // a la altura de los iconos
ctx.move(to: CGPoint(x: 268, y: y))
ctx.addLine(to: CGPoint(x: 392, y: y))
ctx.strokePath()
ctx.move(to: CGPoint(x: 376, y: y + 13))
ctx.addLine(to: CGPoint(x: 393, y: y))
ctx.addLine(to: CGPoint(x: 376, y: y - 13))
ctx.strokePath()

// Título y subtítulo, arriba del todo.
guard let imagen = ctx.makeImage() else { fatalError("no se pudo pintar") }
let lienzo = NSImage(size: NSSize(width: ancho, height: alto))
lienzo.lockFocus()
NSGraphicsContext.current?.cgContext.draw(imagen, in: CGRect(x: 0, y: 0, width: ancho, height: alto))

func escribir(_ texto: String, _ tamaño: Double, _ peso: NSFont.Weight, _ alfa: Double, _ desdeArriba: Double) {
    let atributos: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: tamaño, weight: peso),
        .foregroundColor: NSColor(white: 1, alpha: alfa),
    ]
    let cadena = texto as NSString
    let medida = cadena.size(withAttributes: atributos)
    cadena.draw(at: NSPoint(x: (ancho - medida.width) / 2, y: alto - desdeArriba - medida.height),
                withAttributes: atributos)
}

escribir("SubFix", 30, .semibold, 0.95, 48)
escribir("Subtítulos listos para tu televisor", 14, .regular, 0.6, 88)
lienzo.unlockFocus()

let destino = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("dmg_assets/background.png")
try? FileManager.default.createDirectory(at: destino.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
if let tiff = lienzo.tiffRepresentation, let mapa = NSBitmapImageRep(data: tiff),
   let png = mapa.representation(using: .png, properties: [:]) {
    try png.write(to: destino)
    print("✓ dmg_assets/background.png")
}
