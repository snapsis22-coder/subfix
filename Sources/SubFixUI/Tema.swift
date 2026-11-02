import AppKit
import SwiftUI

/// Los colores de SubFix: el degradado de una llama (naranja → rojo → magenta → morado),
/// con fondo crema de día y ciruela de noche. Películas en naranja-rojo, series en morado.
public enum Tema {
    static let naranja = Color(suave: 1.00, green: 0.584, blue: 0.0)     // #FF9500
    static let rosa = Color(suave: 1.00, green: 0.216, blue: 0.314)      // #FF3750
    static let morado = Color(suave: 0.890, green: 0.082, blue: 0.529)   // #E31587 (magenta: el acento)
    static let lila = Color(suave: 0.565, green: 0.349, blue: 1.0)       // #9059FF
    static let indigo = Color(suave: 0.349, green: 0.165, blue: 0.796)   // #592ACB
    static let cielo = lila
    static let verde = Color(suave: 0.13, green: 0.70, blue: 0.47)
    static let ambar = Color(suave: 0.96, green: 0.62, blue: 0.10)
    static let rojo = Color(suave: 0.86, green: 0.15, blue: 0.24)

    /// La cabecera: la llama entera.
    static let degradado = LinearGradient(colors: [naranja, rosa, morado, lila],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Los botones principales: la parte caliente de la llama.
    static let degradadoBoton = LinearGradient(colors: [naranja, rosa, morado],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let degradadoSerie = LinearGradient(colors: [lila, indigo],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let degradadoPelicula = LinearGradient(colors: [naranja, rosa],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Para lo que pide una mano del usuario (Subdivx): amarillo que tira a naranja.
    static let degradadoAviso = LinearGradient(colors: [Color(suave: 1.0, green: 0.78, blue: 0.25),
                                                        Color(suave: 1.0, green: 0.55, blue: 0.08)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)

    static let fondo = Color(claro: NSColor(suave: 1.0, green: 0.973, blue: 0.949, alpha: 1),
                             oscuro: NSColor(suave: 0.110, green: 0.063, blue: 0.157, alpha: 1))
    static let tarjeta = Color(claro: .white,
                               oscuro: NSColor(suave: 0.165, green: 0.102, blue: 0.231, alpha: 1))
    static let borde = Color(claro: NSColor(suave: 0.965, green: 0.886, blue: 0.894, alpha: 1),
                             oscuro: NSColor(suave: 0.275, green: 0.180, blue: 0.345, alpha: 1))
    /// El magenta para TEXTO: de noche se aclara, o se pierde sobre el fondo ciruela.
    static let acento = Color(claro: NSColor(suave: 0.80, green: 0.04, blue: 0.43, alpha: 1),
                              oscuro: NSColor(suave: 1.0, green: 0.50, blue: 0.74, alpha: 1))
    static let acentoSerie = Color(claro: NSColor(suave: 0.35, green: 0.16, blue: 0.80, alpha: 1),
                                   oscuro: NSColor(suave: 0.72, green: 0.62, blue: 1.0, alpha: 1))
    static let tinta = Color(claro: NSColor(suave: 0.125, green: 0.071, blue: 0.227, alpha: 1),
                             oscuro: NSColor(suave: 0.98, green: 0.95, blue: 1.0, alpha: 1))
    static let tintaSuave = Color(claro: NSColor(suave: 0.43, green: 0.36, blue: 0.50, alpha: 1),
                                  oscuro: NSColor(suave: 0.76, green: 0.68, blue: 0.82, alpha: 1))
}

/// Cuánto se conserva de la saturación original de la paleta (0,64 = 36 % menos intensa que el original).
/// Cambiar este número retoca TODA la app a la vez; el brillo y el tono no se tocan.
/// (Triturador usa la misma regla.)
let intensidadDeLaPaleta = 0.64

extension NSColor {
    convenience init(suave r: Double, green g: Double, blue b: Double, alpha: Double = 1) {
        var tono: CGFloat = 0, saturacion: CGFloat = 0, brillo: CGFloat = 0
        NSColor(red: r, green: g, blue: b, alpha: 1).usingColorSpace(.deviceRGB)?
            .getHue(&tono, saturation: &saturacion, brightness: &brillo, alpha: nil)
        self.init(hue: tono, saturation: saturacion * intensidadDeLaPaleta, brightness: brillo, alpha: alpha)
    }
}

extension Color {
    init(suave r: Double, green g: Double, blue b: Double) {
        self.init(nsColor: NSColor(suave: r, green: g, blue: b))
    }

    /// Un color que cambia solo con el modo claro u oscuro del sistema.
    init(claro: NSColor, oscuro: NSColor) {
        self.init(nsColor: NSColor(name: nil) { apariencia in
            apariencia.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? oscuro : claro
        })
    }
}

// MARK: - Botones

/// El botón grande de la acción principal: píldora con degradado, sombra morada,
/// se ilumina al pasar el ratón y se hunde un poco al pulsarlo.
struct BotonPrincipal: ButtonStyle {
    var compacto = false
    var relleno = Tema.degradadoBoton
    var sombra = Tema.morado

    func makeBody(configuration: Configuration) -> some View {
        Cuerpo(configuration: configuration, compacto: compacto, relleno: relleno, sombra: sombra)
    }

    private struct Cuerpo: View {
        let configuration: Configuration
        let compacto: Bool
        let relleno: LinearGradient
        let sombra: Color
        @Environment(\.isEnabled) private var activo
        @State private var encima = false

        var body: some View {
            configuration.label
                .font(.system(size: compacto ? 12 : 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, compacto ? 14 : 22)
                .padding(.vertical, compacto ? 7 : 11)
                .background(
                    Capsule().fill(relleno)
                        .overlay(Capsule().fill(.white.opacity(encima && activo ? 0.12 : 0)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                )
                .shadow(color: sombra.opacity(activo ? (encima ? 0.55 : 0.35) : 0), radius: encima ? 14 : 9, y: 4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .saturation(activo ? 1 : 0.15)
                .opacity(activo ? 1 : 0.55)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: encima)
                .onHover { encima = $0 }
                .contentShape(Capsule())
        }
    }
}

/// El botón de acompañamiento: blanco (o berenjena de noche) con texto morado.
struct BotonSecundario: ButtonStyle {
    var compacto = false

    func makeBody(configuration: Configuration) -> some View {
        Cuerpo(configuration: configuration, compacto: compacto)
    }

    private struct Cuerpo: View {
        let configuration: Configuration
        let compacto: Bool
        @Environment(\.isEnabled) private var activo
        @State private var encima = false

        var body: some View {
            configuration.label
                .font(.system(size: compacto ? 12 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Tema.acento)
                .padding(.horizontal, compacto ? 12 : 18)
                .padding(.vertical, compacto ? 6 : 10)
                .background(
                    Capsule().fill(Tema.tarjeta)
                        .overlay(Capsule().fill(Tema.morado.opacity(encima && activo ? 0.10 : 0)))
                        .overlay(Capsule().strokeBorder(Tema.morado.opacity(encima ? 0.55 : 0.30), lineWidth: 1))
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(activo ? 1 : 0.45)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: encima)
                .onHover { encima = $0 }
                .contentShape(Capsule())
        }
    }
}

/// Botón redondo de solo icono, para editar o quitar una fila.
struct BotonIcono: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Cuerpo(configuration: configuration)
    }

    private struct Cuerpo: View {
        let configuration: Configuration
        @State private var encima = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(encima ? Tema.acento : Tema.tintaSuave)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Tema.morado.opacity(encima ? 0.12 : 0.05)))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.easeOut(duration: 0.12), value: encima)
                .onHover { encima = $0 }
                .contentShape(Circle())
        }
    }
}
