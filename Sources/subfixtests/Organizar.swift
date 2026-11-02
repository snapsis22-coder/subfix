import Foundation
import OrganizarKit

/// Las pruebas de «Organizar» (lo que era la app Cartelera), con los nombres reales de su
/// biblioteca. Usan el mismo `probar` del arnés de `main.swift`.
func pruebasDeOrganizar() {
    print("\n▸ ORGANIZAR (antes Cartelera)")
    func lee(_ nombre: String, _ esperado: Lectura?) {
        let leido = Analizador.leer(nombre)
        probar("\(nombre) → \(esperado.map { "\($0)" } ?? "nada")") {
            if leido != esperado { print("       salió: \(leido.map { "\($0)" } ?? "nada")") }
            return leido == esperado
        }
    }

    print("\n▸ Películas (nombres reales de su biblioteca)")
    lee("Verity.2026.REPACK.2160p.AMZN.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-BYNDR (SubFix).mkv",
        .pelicula(titulo: "Verity", año: 2026))
    lee("By.Any.Means.2026.2160p.4K.WEB.x265.10bit.AAC5.1-[YTS.GG - YTS.BZ].mkv",
        .pelicula(titulo: "By Any Means", año: 2026))
    lee("THE.INVITE.2026.1080p.AMZN.WEB-DL.DUAL.DDP5.1.H.264-ONIROS.mkv",
        .pelicula(titulo: "The Invite", año: 2026))
    lee("Send Help (2026) [2160p] [4K] [BluRay] [5.1] [YTS.BZ]",
        .pelicula(titulo: "Send Help", año: 2026))
    lee("Full Metal Jacket 1987 REMASTERED 1080p BluRay HEVC x265 5.1 BONE (SubFix).mkv",
        .pelicula(titulo: "Full Metal Jacket", año: 1987))
    lee("The.Dog.Stars.2026.2160p.AMZN.WEB-DL.DV.HDR10+.LAT.DDP5.1.H265.MP4-BTM",
        .pelicula(titulo: "The Dog Stars", año: 2026))
    lee("Spider.Man.Brand.New.Day.2026", .pelicula(titulo: "Spider Man Brand New Day", año: 2026))
    lee("El Agente Secreto (2025)", .pelicula(titulo: "El Agente Secreto", año: 2025))
    lee("Blade.Runner.2049.2017.1080p.BluRay.x264.mkv", .pelicula(titulo: "Blade Runner 2049", año: 2017))
    lee("Solo Mio", .pelicula(titulo: "Solo Mio", año: nil))
    lee("Reminders.of.Him.2160p.AMZN.WEB-DL.mkv", .pelicula(titulo: "Reminders of Him", año: nil))

    print("\n▸ Series")
    lee("Tulsa King S04E02 Blind Rooster 2160p ATV WEB-DL DDP5 1 Atmos DV HDR H 265-FLUX",
        .serie(nombre: "Tulsa King", temporada: 4, episodio: 2))
    lee("Ted.Lasso.S04E01.Home.2160p.10bit.ATVP.WEB-DL.DDP5.1.HEVC-Vyndros.mkv",
        .serie(nombre: "Ted Lasso", temporada: 4, episodio: 1))
    lee("Widows Bay S01E01 Welcome to Widows Bay 2160p ATVP WEB-DL DD 5 1 Atmos DoVi HDR H 265-playWEB.mkv",
        .serie(nombre: "Widows Bay", temporada: 1, episodio: 1))
    lee("Ted Lasso (2022) Season 4", .serie(nombre: "Ted Lasso", temporada: 4, episodio: nil))
    lee("the.office.us.3x07.mkv", .serie(nombre: "The Office Us", temporada: 3, episodio: 7))
    lee("Severance.S02.2160p.ATVP.WEB-DL", .serie(nombre: "Severance", temporada: 2, episodio: nil))

    print("\n▸ Carpetas de destino")
    probar("película con año → «Título (Año)»") {
        Lectura.pelicula(titulo: "Verity", año: 2026).carpeta == "Verity (2026)"
    }
    probar("temporada con dos cifras → «Season 04»") {
        Lectura.serie(nombre: "Tulsa King", temporada: 4, episodio: 2).carpetaDeTemporada == "Season 04"
    }

    // MARK: - Sobre el disco, en una carpeta desechable

    let fm = FileManager.default
    let raiz = fm.temporaryDirectory.appendingPathComponent("carteleratests-\(UUID().uuidString)")
    let entrada = raiz.appendingPathComponent("Descargas")
    let bibliotecas = Bibliotecas(peliculas: raiz.appendingPathComponent("Peliculas"),
                                  series: raiz.appendingPathComponent("Series"))
    try! fm.createDirectory(at: entrada, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: raiz) }

    func crear(_ ruta: String, _ texto: String = "x") {
        let url = entrada.appendingPathComponent(ruta)
        try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! texto.write(to: url, atomically: true, encoding: .utf8)
    }
    func existe(_ url: URL, _ ruta: String) -> Bool { fm.fileExists(atPath: url.appendingPathComponent(ruta).path) }

    crear("Verity.2026.2160p.WEB-DL.mkv")
    crear("Verity.2026.2160p.WEB-DL.srt")
    crear("Verity.2026.2160p.WEB-DL.es.srt")
    crear("Send Help (2026) [2160p] [YTS.BZ]/Send.Help.2026.2160p.mkv")
    crear("Send Help (2026) [2160p] [YTS.BZ]/Send.Help.2026.2160p.srt")
    crear("Send Help (2026) [2160p] [YTS.BZ]/sample/sample.mkv")
    crear("Tulsa King S04E02 Blind Rooster 2160p/Tulsa King S04E02 Blind Rooster 2160p.mkv")
    crear("Ted Lasso (2022) Season 4/Ted.Lasso.S04E01.mkv")
    crear("Ted Lasso (2022) Season 4/Ted.Lasso.S04E02.mkv")
    crear("leeme.txt")

    print("\n▸ Examinar la carpeta de entrada")
    let examenes = Planificador.examinarCarpeta(entrada)
    probar("encuentra 4 descargas e ignora el .txt suelto") { examenes.count == 4 }
    probar("el video suelto lleva sus dos subtítulos") {
        guard let v = examenes.first(where: { $0.origen.lastPathComponent.hasPrefix("Verity") }),
              case .archivo(_, let acompañantes) = v.forma else { return false }
        return acompañantes.count == 2
    }
    probar("la muestra de 1 minuto no cuenta como video") {
        guard let s = examenes.first(where: { $0.origen.lastPathComponent.hasPrefix("Send") }),
              case .carpeta(let videos) = s.forma else { return false }
        return videos.count == 1
    }
    probar("dos episodios de la misma temporada = temporada entera") {
        examenes.first(where: { $0.origen.lastPathComponent.hasPrefix("Ted") })?.lectura
            == .serie(nombre: "Ted Lasso", temporada: 4, episodio: nil)
    }

    print("\n▸ Organizar y deshacer")
    var todos: [Movimiento] = []
    for examen in examenes {
        let movimientos = Planificador.movimientos(examen, como: examen.lectura!, en: bibliotecas)
        let resultado = Planificador.ejecutar(movimientos)
        todos += resultado.hechos
        if let falla = resultado.falla { print("       \(falla.localizedDescription)") }
    }
    probar("película suelta → Peliculas/Verity (2026)/ con sus .srt") {
        existe(bibliotecas.peliculas, "Verity (2026)/Verity.2026.2160p.WEB-DL.mkv")
            && existe(bibliotecas.peliculas, "Verity (2026)/Verity.2026.2160p.WEB-DL.es.srt")
    }
    probar("carpeta de película → renombrada a «Send Help (2026)» con todo dentro") {
        existe(bibliotecas.peliculas, "Send Help (2026)/Send.Help.2026.2160p.srt")
            && existe(bibliotecas.peliculas, "Send Help (2026)/sample/sample.mkv")
    }
    probar("episodio → Series/Tulsa King/Season 04/") {
        existe(bibliotecas.series, "Tulsa King/Season 04/Tulsa King S04E02 Blind Rooster 2160p/Tulsa King S04E02 Blind Rooster 2160p.mkv")
    }
    probar("temporada entera → Series/Ted Lasso/Season 04/") {
        existe(bibliotecas.series, "Ted Lasso/Season 04/Ted.Lasso.S04E02.mkv")
    }
    probar("el .txt suelto no se tocó") { existe(entrada, "leeme.txt") }

    probar("lo ya organizado se reconoce como «en orden»") {
        let enSitio = Planificador.examinar(bibliotecas.peliculas.appendingPathComponent("Send Help (2026)"))!
        let m = Planificador.movimientos(enSitio, como: enSitio.lectura!, en: bibliotecas)
        return Planificador.diagnosticar(m, lectura: enSitio.lectura!) == .enOrden
    }

    probar("nunca sobrescribe: un segundo Verity choca") {
        crear("Verity.2026.1080p.mkv")
        let otro = Planificador.examinar(entrada.appendingPathComponent("Verity.2026.1080p.mkv"))!
        let m = Planificador.movimientos(otro, como: otro.lectura!, en: bibliotecas)
        // La carpeta existe pero el archivo no: puede entrar. Ahora uno con el mismo nombre exacto:
        crear("Otra/Verity.2026.2160p.WEB-DL.mkv")
        let gemelo = Planificador.examinar(entrada.appendingPathComponent("Otra/Verity.2026.2160p.WEB-DL.mkv"))!
        let mg = Planificador.movimientos(gemelo, como: gemelo.lectura!, en: bibliotecas)
        let resultado = Planificador.ejecutar(mg)
        return Planificador.diagnosticar(m, lectura: otro.lectura!) == .listo
            && resultado.hechos.isEmpty && resultado.falla != nil
            && existe(entrada, "Otra/Verity.2026.2160p.WEB-DL.mkv")
    }

    probar("deshacer deja todo como estaba") {
        guard Planificador.deshacer(todos) == nil else { return false }
        return existe(entrada, "Verity.2026.2160p.WEB-DL.mkv")
            && existe(entrada, "Send Help (2026) [2160p] [YTS.BZ]/Send.Help.2026.2160p.mkv")
            && existe(entrada, "Ted Lasso (2022) Season 4/Ted.Lasso.S04E01.mkv")
            && !existe(bibliotecas.peliculas, "Verity (2026)/Verity.2026.2160p.WEB-DL.mkv")
    }
}
