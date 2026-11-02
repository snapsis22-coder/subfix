import OrganizarKit
import SwiftUI
import UniformTypeIdentifiers

/// La sección «Organizar» (lo que antes era la app Cartelera): ordena las descargas en
/// `Título (Año)` y `Serie/Season XX` para Jellyfin y Plex.
struct VistaOrganizar: View {
    @ObservedObject var modelo: Organizador
    /// ScrollView es AppKit y sale en blanco en los retratos: ahí se pinta la lista sin él.
    var sinScroll = false
    @State private var soltando = false

    var body: some View {
        VStack(spacing: 0) {
            TiraDeCarpetas(modelo: modelo)
                .padding(.horizontal, 24)
                .padding(.top, 18)
            contenido
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            BarraOrganizar(modelo: modelo)
        }
        .background(Tema.fondo)
        .onDrop(of: [.fileURL], isTargeted: $soltando) { proveedores in
            recibir(proveedores)
            return true
        }
        .overlay {
            if soltando {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Tema.degradado, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(RoundedRectangle(cornerRadius: 18).fill(Tema.morado.opacity(0.06)))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: soltando)
    }

    @ViewBuilder private var contenido: some View {
        if modelo.visibles.isEmpty {
            ZonaVaciaOrganizar(modelo: modelo)
        } else if sinScroll {
            lista.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { lista }
        }
    }

    private var lista: some View {
        // VStack y no LazyVStack: la lista es corta y así también sale en los retratos.
        VStack(spacing: 10) {
            ForEach(modelo.visibles) { fila in
                FilaDeDescarga(modelo: modelo, fila: fila)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private func recibir(_ proveedores: [NSItemProvider]) {
        for proveedor in proveedores {
            _ = proveedor.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in modelo.agregar([url]) }
            }
        }
    }
}

/// Píldora con interruptor para la cabecera morada (Automático, Vigilar…).
struct InterruptorAutomatico: View {
    @Binding var encendido: Bool
    var titulo = "Automático"
    var textoEncendido = "Vigilando descargas"
    var icono = "bolt"
    var ayuda = "Organiza solo lo que termine de bajar en la carpeta de entrada, cada 30 segundos, mientras la app esté abierta"
    var activo = true
    @State private var encima = false

    var body: some View {
        Button { encendido.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: encendido ? "\(icono).fill" : "\(icono).slash.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(encendido ? Tema.morado : .white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(encendido ? .white : .white.opacity(0.18)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(titulo)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    Text(encendido ? textoEncendido : "Apagado")
                        .font(.system(size: 10.5, weight: .medium))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                // El interruptor dibujado a mano: el del sistema se ve gris sobre el morado.
                Capsule()
                    .fill(encendido ? .white : .white.opacity(0.25))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: encendido ? .trailing : .leading) {
                        Circle().fill(encendido ? Tema.morado : .white)
                            .frame(width: 16, height: 16).padding(2)
                    }
            }
            .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(encima ? 0.22 : 0.14)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!activo)
        .opacity(activo ? 1 : 0.55)
        .onHover { encima = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: encendido)
        .help(ayuda)
    }
}

// MARK: - Carpetas

struct TiraDeCarpetas: View {
    @ObservedObject var modelo: Organizador

    var body: some View {
        HStack(spacing: 12) {
            TarjetaCarpeta(icono: "tray.and.arrow.down.fill", titulo: "Entrada", color: Tema.ambar,
                           url: modelo.entrada) { modelo.elegir(.entrada) }
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Tema.acento.opacity(0.6))
            TarjetaCarpeta(icono: "film.fill", titulo: "Películas", color: Tema.morado,
                           url: modelo.peliculas) { modelo.elegir(.peliculas) }
            TarjetaCarpeta(icono: "tv.fill", titulo: "Series", color: Tema.indigo,
                           url: modelo.series) { modelo.elegir(.series) }
        }
    }
}

struct TarjetaCarpeta: View {
    let icono: String
    let titulo: String
    let color: Color
    let url: URL?
    let elegir: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: elegir) {
            HStack(spacing: 11) {
                Image(systemName: icono)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.13)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo.uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Tema.tintaSuave)
                    Text(url?.lastPathComponent ?? "Elegir carpeta…")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(url == nil ? Tema.acento : Tema.tinta)
                        .lineLimit(1)
                    Text(url.map { abreviar($0.deletingLastPathComponent().path) } ?? "Sin elegir")
                        .font(.system(size: 10))
                        .foregroundStyle(Tema.tintaSuave)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Tema.tintaSuave.opacity(encima ? 1 : 0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Tema.tarjeta))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(encima ? color.opacity(0.5) : Tema.borde, lineWidth: 1))
            .shadow(color: Tema.morado.opacity(0.12), radius: encima ? 12 : 8, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .animation(.easeOut(duration: 0.15), value: encima)
        .help(url?.path ?? "Elegir carpeta")
    }

    private func abreviar(_ ruta: String) -> String {
        ruta.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

// MARK: - Lista vacía

struct ZonaVaciaOrganizar: View {
    @ObservedObject var modelo: Organizador

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Tema.morado.opacity(0.10)).frame(width: 110, height: 110)
                Circle().fill(Tema.morado.opacity(0.08)).frame(width: 150, height: 150)
                Image(systemName: modelo.enOrden > 0 ? "checkmark.seal.fill" : "sparkles.rectangle.stack.fill")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(Tema.degradado)
            }
            VStack(spacing: 6) {
                Text(modelo.enOrden > 0 ? "Todo está en orden" : "Arrastra aquí películas o series")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.tinta)
                Text(modelo.enOrden > 0
                     ? "\(modelo.enOrden) \(modelo.enOrden == 1 ? "descarga ya está" : "descargas ya están") donde deben. Suelta algo nuevo o revisa otra vez."
                     : "O pulsa «Revisar entrada» para ver qué hay en \(modelo.entrada?.lastPathComponent ?? "tu carpeta de descargas").")
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.tintaSuave)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            HStack(spacing: 8) {
                Ejemplo(icono: "film", texto: "Verity (2026)")
                Ejemplo(icono: "tv", texto: "Tulsa King › Season 04")
            }
            .padding(.top, 4)
        }
        .padding(40)
    }

    private struct Ejemplo: View {
        let icono: String
        let texto: String
        var body: some View {
            Label(texto, systemImage: icono)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Tema.acento)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Tema.morado.opacity(0.08)))
        }
    }
}

// MARK: - Descarga

struct FilaDeDescarga: View {
    @ObservedObject var modelo: Organizador
    let fila: Descarga
    @State private var editando = false
    @State private var encima = false

    private var estado: EstadoDeDescarga { modelo.estado(de: fila) }
    private var esSerie: Bool { fila.lectura?.esSerie ?? false }
    private var activa: Bool { fila.incluida || fila.resultado != nil }

    var body: some View {
        HStack(spacing: 14) {
            Casilla(marcada: fila.incluida, visible: fila.resultado == nil && estado != .noEntiendo) {
                modelo.alternar(fila.id)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(esSerie ? Tema.degradadoSerie : Tema.degradadoPelicula)
                Image(systemName: fila.lectura == nil ? "questionmark" : (esSerie ? "tv" : "film"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .shadow(color: (esSerie ? Tema.indigo : Tema.morado).opacity(0.3), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(fila.lectura?.carpeta ?? fila.examen.origen.lastPathComponent)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tema.tinta)
                        .lineLimit(1)
                    if let chip = chip { Chip(texto: chip, color: esSerie ? Tema.acentoSerie : Tema.acento) }
                }
                if !modelo.rutaCorta(de: fila).isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill").font(.system(size: 9))
                        Text(modelo.rutaCorta(de: fila).joined(separator: "  ›  "))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(esSerie ? Tema.acentoSerie : Tema.acento)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 9))
                    Text(fila.examen.origen.lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Tema.tintaSuave)
            }

            Spacer(minLength: 8)

            EtiquetaDeEstado(estado: estado)

            if fila.resultado == nil {
                Button { editando = true } label: { Image(systemName: "pencil") }
                    .buttonStyle(BotonIcono())
                    .help("Corregir el nombre")
                    .popover(isPresented: $editando, arrowEdge: .bottom) {
                        EditorDeNombre(lectura: fila.lectura ?? .pelicula(titulo: "", año: nil)) { nueva in
                            modelo.corregir(fila.id, a: nueva)
                            editando = false
                        } cancelar: { editando = false }
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Tema.tarjeta))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(encima ? Tema.morado.opacity(0.35) : Tema.borde, lineWidth: 1))
        .shadow(color: Tema.morado.opacity(encima ? 0.12 : 0.05), radius: encima ? 10 : 5, y: 3)
        .opacity(activa ? 1 : 0.55)
        .onHover { encima = $0 }
        .animation(.easeOut(duration: 0.15), value: encima)
    }

    private var chip: String? {
        switch fila.lectura {
        case .pelicula?: return "Película"   // el año ya va en el título
        case .serie(_, let t, let e?)?: return String(format: "T%02d · E%02d", t, e)
        case .serie(_, let t, nil)?: return "Temporada \(t) completa"
        case nil: return nil
        }
    }
}

struct Chip: View {
    let texto: String
    let color: Color
    var body: some View {
        Text(texto)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

/// La casilla redonda de cada fila: morada y con palomita cuando va incluida.
struct Casilla: View {
    let marcada: Bool
    let visible: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            ZStack {
                Circle().strokeBorder(marcada ? Color.clear : Tema.tintaSuave.opacity(0.45), lineWidth: 1.5)
                if marcada {
                    Circle().fill(Tema.degradadoBoton)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .disabled(!visible)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: marcada)
        .help(marcada ? "Se va a organizar" : "Se va a dejar quieta")
    }
}

struct EtiquetaDeEstado: View {
    let estado: EstadoDeDescarga

    var body: some View {
        HStack(spacing: 5) {
            if estado == .moviendo {
                ProgressView().controlSize(.mini).tint(color)
            } else {
                Image(systemName: icono).font(.system(size: 10, weight: .bold))
            }
            Text(texto).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
        .help(ayuda)
    }

    private var texto: String {
        switch estado {
        case .listo: return "Listo"
        case .sinAño: return "Sin año"
        case .noEntiendo: return "No la entiendo"
        case .enOrden: return "En orden"
        case .choque: return "Ya existe"
        case .moviendo: return "Moviendo…"
        case .hecho: return "Organizada"
        case .fallo: return "Falló"
        }
    }

    private var icono: String {
        switch estado {
        case .listo: return "sparkles"
        case .sinAño: return "calendar.badge.exclamationmark"
        case .noEntiendo: return "questionmark.circle.fill"
        case .enOrden, .hecho: return "checkmark.circle.fill"
        case .choque: return "exclamationmark.triangle.fill"
        case .moviendo: return ""
        case .fallo: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch estado {
        case .listo, .moviendo: return Tema.acento
        case .sinAño, .noEntiendo: return Tema.ambar
        case .enOrden, .hecho: return Tema.verde
        case .choque, .fallo: return Tema.rojo
        }
    }

    private var ayuda: String {
        switch estado {
        case .listo: return "Se moverá al pulsar Organizar"
        case .sinAño: return "Sin año, Jellyfin puede confundirla con otra del mismo nombre. Corrígela con el lápiz."
        case .noEntiendo: return "No pude leer el nombre. Corrígelo con el lápiz."
        case .enOrden: return "Ya está donde debe"
        case .choque(let nombre): return "Ya hay algo llamado «\(nombre)» en el destino. No se sobrescribe nunca."
        case .moviendo: return "Moviendo…"
        case .hecho: return "Organizada"
        case .fallo(let motivo): return motivo
        }
    }
}

// MARK: - Corregir a mano

struct EditorDeNombre: View {
    let guardar: (Lectura) -> Void
    let cancelar: () -> Void

    @State private var esSerie: Bool
    @State private var titulo: String
    @State private var año: String
    @State private var temporada: String
    @State private var episodio: Int?

    init(lectura: Lectura, guardar: @escaping (Lectura) -> Void, cancelar: @escaping () -> Void) {
        self.guardar = guardar
        self.cancelar = cancelar
        switch lectura {
        case .pelicula(let t, let a):
            _esSerie = State(initialValue: false)
            _titulo = State(initialValue: t)
            _año = State(initialValue: a.map(String.init) ?? "")
            _temporada = State(initialValue: "1")
        case .serie(let n, let t, let e):
            _esSerie = State(initialValue: true)
            _titulo = State(initialValue: n)
            _año = State(initialValue: "")
            _temporada = State(initialValue: String(t))
            _episodio = State(initialValue: e)
        }
    }

    private var resultado: Lectura? {
        let limpio = titulo.trimmingCharacters(in: .whitespaces)
        guard !limpio.isEmpty else { return nil }
        if esSerie {
            guard let t = Int(temporada), t >= 0 else { return nil }
            return .serie(nombre: limpio, temporada: t, episodio: episodio)
        }
        let a = Int(año.trimmingCharacters(in: .whitespaces))
        if !año.isEmpty, a == nil { return nil }
        return .pelicula(titulo: limpio, año: a)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Corregir")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Tema.tinta)

            Picker("", selection: $esSerie) {
                Text("Película").tag(false)
                Text("Serie").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            campo(esSerie ? "Nombre de la serie" : "Título") {
                TextField(esSerie ? "Tulsa King" : "Verity", text: $titulo)
            }
            if esSerie {
                campo("Temporada") { TextField("4", text: $temporada).frame(width: 80) }
            } else {
                campo("Año") { TextField("2026", text: $año).frame(width: 80) }
            }

            if let resultado {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                    Text(resultado.carpetaDeTemporada.map { "\(resultado.carpeta)  ›  \($0)" } ?? resultado.carpeta)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Tema.acento)
            }

            HStack {
                Spacer()
                Button("Cancelar", action: cancelar).buttonStyle(BotonSecundario(compacto: true))
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") { if let resultado { guardar(resultado) } }
                    .buttonStyle(BotonPrincipal(compacto: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(resultado == nil)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(18)
        .frame(width: 320)
    }

    private func campo<C: View>(_ etiqueta: String, @ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(etiqueta).font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.tintaSuave)
            contenido()
        }
    }
}

// MARK: - Barra inferior

struct BarraOrganizar: View {
    @ObservedObject var modelo: Organizador

    var body: some View {
        HStack(spacing: 10) {
            resumen
            Spacer()
            if !modelo.ultimoLote.isEmpty {
                Button { Task { await modelo.deshacer() } } label: {
                    Label("Deshacer", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(BotonSecundario())
                .disabled(modelo.trabajando)
            }
            if modelo.filas.contains(where: { $0.resultado == .hecho }) {
                Button { modelo.limpiarHechas() } label: {
                    Label("Limpiar lista", systemImage: "checklist.checked")
                }
                .buttonStyle(BotonSecundario())
                .disabled(modelo.trabajando)
            }
            Button { modelo.revisarEntrada() } label: {
                Label("Revisar entrada", systemImage: "arrow.clockwise")
            }
            .buttonStyle(BotonSecundario())
            .disabled(modelo.trabajando || modelo.entrada == nil)
            .keyboardShortcut("r")

            Button { Task { await modelo.organizar() } } label: {
                Label(modelo.porMover.isEmpty ? "Organizar" : "Organizar \(modelo.porMover.count)",
                      systemImage: "wand.and.stars")
            }
            .buttonStyle(BotonPrincipal())
            .disabled(modelo.porMover.isEmpty || modelo.trabajando || modelo.bibliotecas == nil)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Tema.tarjeta)
        .overlay(alignment: .top) { Rectangle().fill(Tema.borde).frame(height: 1) }
    }

    @ViewBuilder private var resumen: some View {
        if let mensaje = modelo.mensaje {
            Label(mensaje, systemImage: "checkmark.circle.fill")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Tema.verde)
        } else if modelo.bibliotecas == nil {
            Label("Elige dónde van las películas y las series", systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Tema.ambar)
        } else {
            let revisar = modelo.visibles.filter {
                let e = modelo.estado(de: $0)
                return e == .sinAño || e == .noEntiendo
            }.count
            HStack(spacing: 14) {
                Dato(numero: modelo.porMover.count, texto: "por organizar", color: Tema.acento)
                if revisar > 0 { Dato(numero: revisar, texto: "por revisar", color: Tema.ambar) }
                if modelo.enOrden > 0 { Dato(numero: modelo.enOrden, texto: "en orden", color: Tema.verde) }
            }
        }
    }

    private struct Dato: View {
        let numero: Int
        let texto: String
        let color: Color
        var body: some View {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text("\(numero)").font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundStyle(Tema.tinta)
                Text(texto).font(.system(size: 12)).foregroundStyle(Tema.tintaSuave)
            }
        }
    }
}
