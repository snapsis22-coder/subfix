#!/usr/bin/env swift
// Dibuja el icono de SubFix por código y arma el .icns.
//
//     swift herramientas/hacer_icono.swift
//
// Igual que el candado de Bóveda: nada de recursos externos, todo CoreGraphics,
// así el icono se puede retocar cambiando números en vez de abrir un editor.

import AppKit

let lado = 1024.0

/// El color del fondo y, cuando hace falta, el del marco del televisor: sobre
/// fondos oscuros un marco negro desaparece, así que ahí el TV va plateado.
struct Paleta {
    let nombre: String
    let arriba: (Double, Double, Double)
    let abajo: (Double, Double, Double)
    var marco: (Double, Double, Double) = (0.13, 0.16, 0.25)
    var pie: (Double, Double, Double) = (0.11, 0.14, 0.22)
}

let paletas: [Paleta] = [
    Paleta(nombre: "Azul del sistema", arriba: (0.31, 0.58, 0.99), abajo: (0.09, 0.29, 0.83)),
    Paleta(nombre: "Índigo de sala de cine", arriba: (0.36, 0.30, 0.82), abajo: (0.13, 0.09, 0.42)),
    Paleta(nombre: "Grafito con TV plateado", arriba: (0.35, 0.38, 0.43), abajo: (0.13, 0.15, 0.18),
           marco: (0.80, 0.83, 0.88), pie: (0.72, 0.75, 0.80)),
    Paleta(nombre: "Verde azulado", arriba: (0.16, 0.72, 0.70), abajo: (0.03, 0.40, 0.46)),
    Paleta(nombre: "Vino de telón", arriba: (0.72, 0.24, 0.26), abajo: (0.36, 0.07, 0.12)),
    Paleta(nombre: "Noche con TV plateado", arriba: (0.20, 0.22, 0.28), abajo: (0.05, 0.05, 0.08),
           marco: (0.78, 0.81, 0.87), pie: (0.70, 0.73, 0.79)),
]

/// Un televisor con dos líneas de subtítulo dentro, como se ven de verdad:
/// blancas, centradas y pegadas al borde inferior de la pantalla.
func dibujar(_ ctx: CGContext, _ paleta: Paleta = paletas[0]) {
    let espacio = CGColorSpaceCreateDeviceRGB()
    func color(_ r: Double, _ v: Double, _ a: Double, _ alfa: Double = 1) -> CGColor {
        CGColor(red: r, green: v, blue: a, alpha: alfa)
    }
    func redondeado(_ r: CGRect, _ radio: Double) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radio, cornerHeight: radio, transform: nil)
    }

    // Fondo: el rectángulo redondeado de macOS con degradado azul.
    let fondo = CGRect(x: 0, y: 0, width: lado, height: lado)
        .insetBy(dx: lado * 0.08, dy: lado * 0.08)
    ctx.saveGState()
    ctx.addPath(redondeado(fondo, lado * 0.2237))       // la curva de los iconos del sistema
    ctx.clip()
    ctx.drawLinearGradient(CGGradient(colorsSpace: espacio,
                                      colors: [color(paleta.arriba.0, paleta.arriba.1, paleta.arriba.2),
                                               color(paleta.abajo.0, paleta.abajo.1, paleta.abajo.2)] as CFArray,
                                      locations: [0, 1])!,
                           start: CGPoint(x: 0, y: lado), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // El pie del televisor, primero: el cuerpo lo tapa por arriba.
    ctx.setFillColor(color(paleta.pie.0, paleta.pie.1, paleta.pie.2))
    let cuello = CGRect(x: lado * 0.470, y: lado * 0.270, width: lado * 0.06, height: lado * 0.105)
    let base = CGRect(x: lado * 0.365, y: lado * 0.252, width: lado * 0.27, height: lado * 0.040)
    ctx.addPath(redondeado(cuello, lado * 0.010))
    ctx.addPath(redondeado(base, lado * 0.020))
    ctx.fillPath()

    // Cuerpo: marco oscuro con las esquinas suaves. Deja aire hasta el borde del
    // fondo; pegado se ve apretado a tamaño pequeño.
    let cuerpo = CGRect(x: lado * 0.190, y: lado * 0.355, width: lado * 0.62, height: lado * 0.390)
    ctx.setFillColor(color(paleta.marco.0, paleta.marco.1, paleta.marco.2))
    ctx.addPath(redondeado(cuerpo, lado * 0.044))
    ctx.fillPath()

    // Pantalla: casi negra, con un brillo muy leve de arriba abajo.
    let pantalla = cuerpo.insetBy(dx: lado * 0.028, dy: lado * 0.028)
    ctx.saveGState()
    ctx.addPath(redondeado(pantalla, lado * 0.026))
    ctx.clip()
    ctx.drawLinearGradient(CGGradient(colorsSpace: espacio,
                                      colors: [color(0.10, 0.14, 0.25),
                                               color(0.04, 0.05, 0.10)] as CFArray,
                                      locations: [0, 1])!,
                           start: CGPoint(x: 0, y: pantalla.maxY),
                           end: CGPoint(x: 0, y: pantalla.minY), options: [])
    ctx.restoreGState()

    // Reflejo: una banda diagonal clarísima para que la pantalla parezca cristal.
    ctx.saveGState()
    ctx.addPath(redondeado(pantalla, lado * 0.026))
    ctx.clip()
    ctx.setFillColor(color(1, 1, 1, 0.055))
    ctx.move(to: CGPoint(x: pantalla.minX, y: pantalla.maxY))
    ctx.addLine(to: CGPoint(x: pantalla.minX + pantalla.width * 0.52, y: pantalla.maxY))
    ctx.addLine(to: CGPoint(x: pantalla.minX, y: pantalla.maxY - pantalla.height * 0.72))
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()

    // Los subtítulos: dos líneas blancas centradas, la segunda más corta, pegadas
    // al borde inferior — que es donde el ojo espera encontrarlas.
    ctx.setFillColor(color(1, 1, 1, 0.96))
    let alto = lado * 0.038
    for (indice, ancho) in [0.36, 0.23].enumerated() {
        let y = pantalla.minY + lado * (indice == 0 ? 0.083 : 0.032)
        let linea = CGRect(x: pantalla.midX - lado * ancho / 2, y: y,
                           width: lado * ancho, height: alto)
        ctx.addPath(redondeado(linea, alto / 2))
    }
    ctx.fillPath()
}

// MARK: - Pintar

func lienzo(_ medida: Int, _ pintar: (CGContext) -> Void) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: medida, height: medida, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    pintar(ctx)
    return ctx.makeImage()
}

// MARK: - Lámina de variantes

/// `--variantes` pinta todas las paletas juntas, numeradas, para poder elegir
/// mirando en vez de imaginando.
if CommandLine.arguments.contains("--variantes") {
    let celda = 320.0, columnas = 3.0, hueco = 26.0, etiqueta = 34.0
    let filas = ceil(Double(paletas.count) / columnas)
    let ancho = columnas * celda + (columnas + 1) * hueco
    let alto = filas * (celda + etiqueta) + (filas + 1) * hueco

    let lamina = NSImage(size: NSSize(width: ancho, height: alto))
    lamina.lockFocus()
    NSColor(white: 0.93, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: ancho, height: alto).fill()

    for (indice, paleta) in paletas.enumerated() {
        guard let imagen = lienzo(Int(lado), { dibujar($0, paleta) }) else { continue }
        let columna = Double(indice).truncatingRemainder(dividingBy: columnas)
        let fila = floor(Double(indice) / columnas)
        let x = hueco + columna * (celda + hueco)
        let y = alto - (hueco + (fila + 1) * (celda + etiqueta)) + etiqueta

        NSGraphicsContext.current?.cgContext.draw(
            imagen, in: CGRect(x: x, y: y, width: celda, height: celda))

        let texto = "\(indice + 1). \(paleta.nombre)" as NSString
        texto.draw(at: NSPoint(x: x + 6, y: y - etiqueta + 8), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: NSColor.black,
        ])
    }
    lamina.unlockFocus()

    let destino = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/SubFix-fondos.png")
    if let tiff = lamina.tiffRepresentation, let mapa = NSBitmapImageRep(data: tiff),
       let png = mapa.representation(using: .png, properties: [:]) {
        try png.write(to: destino)
        print("✓ \(destino.path)")
    }
    exit(0)
}

// MARK: - Exportar

// `--paleta N` elige el fondo (1 = el primero de la lista). El elegido para la
// app es el grafito con televisor plateado: es el que se lee a 32 px, y no
// compite con el azul de Calculadora+ ni de Peek a Boo en el Dock.
var paletaElegida = paletas[2]
if let posicion = CommandLine.arguments.firstIndex(of: "--paleta"),
   posicion + 1 < CommandLine.arguments.count,
   let numero = Int(CommandLine.arguments[posicion + 1]),
   (1...paletas.count).contains(numero) {
    paletaElegida = paletas[numero - 1]
    print("  paleta: \(paletaElegida.nombre)")
}

let carpeta = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = carpeta.appendingPathComponent("Resources/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let espacio = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(lado), height: Int(lado), bitsPerComponent: 8,
                          bytesPerRow: 0, space: espacio,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no se pudo crear el lienzo")
}
dibujar(ctx, paletaElegida)
guard let maestra = ctx.makeImage() else { fatalError("no se pudo pintar") }

// Los tamaños que pide iconutil.
let medidas: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
    (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (medida, nombre) in medidas {
    guard let chico = CGContext(data: nil, width: medida, height: medida, bitsPerComponent: 8,
                                bytesPerRow: 0, space: espacio,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    chico.interpolationQuality = .high
    chico.draw(maestra, in: CGRect(x: 0, y: 0, width: medida, height: medida))
    guard let imagen = chico.makeImage() else { continue }
    let mapa = NSBitmapImageRep(cgImage: imagen)
    mapa.size = NSSize(width: medida, height: medida)
    guard let png = mapa.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: iconset.appendingPathComponent("\(nombre).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path,
                      "-o", carpeta.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "✗ iconutil falló")
