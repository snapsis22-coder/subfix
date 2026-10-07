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

    /// La barra verde en varios puntos de avance, para revisarla sin abrir la app.
    @MainActor
    public static func barras() -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach([0.0, 0.07, 0.42, 0.83, 1.0], id: \.self) { f in
                BarraVerde(fraccion: f, inicio: Date().addingTimeInterval(-90 * f))
            }
        }
        .padding(28)
    }

    /// Variantes del «listo» al lado derecho de la fila, para elegir mirando.
    @MainActor
    public static func ejemplosDeCheck() -> some View {
        let verde = Color(red: 0.20, green: 0.78, blue: 0.35)
        let oscuro = Color(red: 0.10, green: 0.62, blue: 0.27)

        func fila<D: View>(_ etiqueta: String, @ViewBuilder derecha: () -> D) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(etiqueta).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Unabomber.2026.2160p.4K.WEB.x265.10bit.AAC5.1.mkv").lineLimit(1).truncationMode(.middle)
                        Text("MKV creado: Unabomber (SubFix).mkv").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    derecha()
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))
            }
        }

        return VStack(alignment: .leading, spacing: 14) {
            fila("A · Check simple, grande") {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28)).foregroundStyle(verde)
            }
            fila("B · Sello verde con brillo (como la barra)") {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.30, green: 0.85, blue: 0.42), oscuro],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .top) {
                            Capsule().fill(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0)],
                                                          startPoint: .top, endPoint: .bottom))
                                .frame(width: 18, height: 9).padding(.top, 3)
                        }
                        .shadow(color: verde.opacity(0.55), radius: 6)
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
            }
            fila("C · Etiqueta «Listo» en cápsula") {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                    Text("Listo").font(.callout.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(LinearGradient(colors: [Color(red: 0.30, green: 0.85, blue: 0.42), oscuro],
                                                          startPoint: .top, endPoint: .bottom)))
                .shadow(color: verde.opacity(0.45), radius: 4)
            }
            fila("D · Sello + acceso directo al archivo") {
                HStack(spacing: 10) {
                    Label("Mostrar", systemImage: "folder").font(.callout)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                    ZStack {
                        Circle().fill(verde).shadow(color: verde.opacity(0.5), radius: 5)
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    }
                    .frame(width: 28, height: 28)
                }
            }
        }
        .padding(20)
    }

    /// Los fotogramas de la animación del sello, de izquierda a derecha.
    @MainActor
    public static func tiraDelSello() -> some View {
        let cuadros: [(String, CGFloat, Double, Double, Double)] = [
            ("1 aparece", 1.9, 0.35, -14, 0), ("2 grande", 1.9, 1, -14, 0), ("3 cae", 1.3, 1, -5, 0),
            ("4 impacto", 1.0, 1, 0, 0.2), ("5 onda", 1.0, 1, 0, 0.6), ("6 final", 1.0, 1, 0, 0),
        ]
        return HStack(spacing: 18) {
            ForEach(cuadros, id: \.0) { c in
                VStack(spacing: 8) {
                    CuadroDelSello(escala: c.1, opacidad: c.2, giro: c.3, onda: c.4)
                        .frame(width: 80, height: 80)
                    Text(c.0).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }

    /// Una fila terminada y una pendiente, una sobre otra, para revisar la disposición.
    @MainActor
    public static func filasDeEjemplo() -> some View {
        var lista = Fila(url: URL(fileURLWithPath: "/p/Unabomber.2026.2160p.4K.WEB.x265.10bit.AAC5.1-[YTS.GG - YTS.BZ].mkv"))
        lista.estado = .hecha("MKV creado: Unabomber.2026.2160p.4K.WEB.x265.10bit.AAC5.1-[YTS.GG - YTS.BZ] (SubFix).mkv")
        var pendiente = Fila(url: URL(fileURLWithPath: "/p/Otra.Pelicula.2025.1080p.WEB-DL.mkv"))
        pendiente.estado = .listaParaProcesar
        var avisada = Fila(url: URL(fileURLWithPath: "/p/Tercera.Pelicula.2024.mkv"))
        avisada.estado = .avisada("no conseguí latino: dejé el de España · búscalo en Subdivx y arrastra aquí lo que bajes")
        return VStack(spacing: 0) {
            ForEach([lista, pendiente, avisada]) { fila in
                FilaDePelicula(fila: fila, preferirLatino: true, elegirPista: { _ in }, crearMKV: {})
                    .padding(.horizontal, 14)
                Divider()
            }
        }
        .padding(.top, 10)
    }
}
