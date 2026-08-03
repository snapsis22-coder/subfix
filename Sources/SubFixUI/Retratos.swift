import SwiftUI

/// Puerta pública para que la herramienta de retratos pueda pintar cada pantalla
/// por separado, sin volver públicas las vistas ni abrir una ventana de verdad.
public enum Retratos {

    @MainActor
    public static func peliculas(_ cola: Cola) -> some View {
        VistaPeliculas(cola: cola)
    }

    @MainActor
    public static func vigilancia(_ vigilante: Vigilante) -> some View {
        VistaVigilancia(vigilante: vigilante)
    }
}
