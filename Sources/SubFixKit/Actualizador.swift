import CryptoKit
import Foundation

/// Una versión publicada en GitHub más nueva que la instalada.
public struct VersionNueva: Equatable, Sendable {
    public let version: String
    public let notas: String
    public let urlDMG: URL
    public let pagina: URL
    /// SHA-256 del DMG según GitHub («digest» del asset); nil si la Release es vieja y no lo trae.
    public let sha256: String?
}

/// Busca en las Releases de GitHub, descarga el DMG, comprueba que sea de verdad y reemplaza
/// la app. Sin Sparkle: la app no está notarizada (certificado propio), así que la confianza
/// se apoya en dos cosas — el hash que publica GitHub y que la app nueva esté firmada con
/// **el mismo certificado** que la instalada.
public enum Actualizador {

    public static let repositorio = "snapsis22-coder/subfix"

    /// `SUBFIX_VERSION_FINGIDA=1.0` hace creer a la app que es vieja: sirve para probar
    /// la actualización de punta a punta sin publicar una versión de mentira.
    public static var versionActual: String {
        ProcessInfo.processInfo.environment["SUBFIX_VERSION_FINGIDA"]
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: Versiones

    /// «v1.3.10» > «1.3.9»; ignora la «v» inicial y lo que venga tras un guion (-beta).
    public static func esMasNueva(_ candidata: String, que actual: String) -> Bool {
        func partes(_ texto: String) -> [Int] {
            var limpio = texto.trimmingCharacters(in: .whitespaces)
            if limpio.lowercased().hasPrefix("v") { limpio.removeFirst() }
            limpio = String(limpio.split(separator: "-").first ?? "")
            return limpio.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = partes(candidata), b = partes(actual)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: GitHub

    private struct Publicacion: Decodable {
        struct Archivo: Decodable {
            let name: String
            let browser_download_url: URL
            let digest: String?
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Archivo]
    }

    /// Lee la respuesta de `releases/latest`. Nil si no hay nada más nuevo que `actual`
    /// o si la Release no trae un .dmg.
    public static func interpretar(_ datos: Data, actual: String) throws -> VersionNueva? {
        let p = try JSONDecoder().decode(Publicacion.self, from: datos)
        guard p.draft != true, p.prerelease != true,
              esMasNueva(p.tag_name, que: actual),
              let dmg = p.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else { return nil }
        var hash = dmg.digest?.lowercased()
        if let h = hash, h.hasPrefix("sha256:") { hash = String(h.dropFirst(7)) } else { hash = nil }
        var version = p.tag_name
        if version.lowercased().hasPrefix("v") { version.removeFirst() }
        return VersionNueva(version: version, notas: p.body ?? "", urlDMG: dmg.browser_download_url,
                            pagina: p.html_url, sha256: hash)
    }

    public static func buscar(actual: String = versionActual) async throws -> VersionNueva? {
        var peticion = URLRequest(url: URL(string: "https://api.github.com/repos/\(repositorio)/releases/latest")!)
        peticion.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        peticion.setValue("SubFix/\(actual)", forHTTPHeaderField: "User-Agent")
        peticion.timeoutInterval = 15
        let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
        guard let http = respuesta as? HTTPURLResponse, http.statusCode == 200 else {
            throw ErrorDeSubFix.fallóLaActualización("GitHub respondió \((respuesta as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return try interpretar(datos, actual: actual)
    }

    // MARK: Descarga

    public static func sha256(de archivo: URL) throws -> String {
        let datos = try Data(contentsOf: archivo, options: .mappedIfSafe)
        return SHA256.hash(data: datos).map { String(format: "%02x", $0) }.joined()
    }

    /// Baja el DMG a una carpeta temporal, avisando del avance, y comprueba su hash.
    public static func descargar(_ version: VersionNueva,
                                 progreso: @escaping @Sendable (Double) -> Void) async throws -> URL {
        var peticion = URLRequest(url: version.urlDMG)
        peticion.setValue("SubFix/\(versionActual)", forHTTPHeaderField: "User-Agent")
        let (bytes, respuesta) = try await URLSession.shared.bytes(for: peticion)
        guard (respuesta as? HTTPURLResponse)?.statusCode == 200 else {
            throw ErrorDeSubFix.fallóLaActualización("no se pudo descargar el DMG")
        }
        let total = max(1, respuesta.expectedContentLength)
        let destino = FileManager.default.temporaryDirectory.appendingPathComponent("SubFix-\(version.version).dmg")
        FileManager.default.createFile(atPath: destino.path, contents: nil)
        let manejador = try FileHandle(forWritingTo: destino)
        defer { try? manejador.close() }

        var trozo = Data(), recibidos: Int64 = 0
        trozo.reserveCapacity(1 << 20)
        for try await byte in bytes {
            trozo.append(byte)
            if trozo.count >= 1 << 20 {
                manejador.write(trozo)
                recibidos += Int64(trozo.count)
                trozo.removeAll(keepingCapacity: true)
                progreso(min(1, Double(recibidos) / Double(total)))
            }
        }
        if !trozo.isEmpty { manejador.write(trozo) }
        try manejador.close()
        progreso(1)

        if let esperado = version.sha256, try sha256(de: destino) != esperado {
            throw ErrorDeSubFix.fallóLaActualización("la descarga no coincide con el hash que publica GitHub; no se instala")
        }
        return destino
    }

    // MARK: Preparar y verificar

    /// Abre el DMG, copia la app a una carpeta temporal y comprueba que sea válida y
    /// de los mismos dueños que la instalada. Devuelve la app lista para instalar.
    public static func prepararEnTemporal(dmg: URL, esperando version: String? = nil,
                                          comparandoCon instalada: URL = Bundle.main.bundleURL) throws -> URL {
        let gestor = FileManager.default
        let montaje = gestor.temporaryDirectory.appendingPathComponent("subfix-dmg-\(UUID().uuidString)")
        let preparada = gestor.temporaryDirectory.appendingPathComponent("subfix-nueva-\(UUID().uuidString)")
        try gestor.createDirectory(at: montaje, withIntermediateDirectories: true)
        try gestor.createDirectory(at: preparada, withIntermediateDirectories: true)

        let abrir = try Herramientas.correr("hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly",
                                                         "-mountpoint", montaje.path, "-quiet"])
        guard abrir.codigo == 0 else {
            throw ErrorDeSubFix.fallóLaActualización("no se pudo abrir el DMG: \(abrir.error)")
        }
        defer { _ = try? Herramientas.correr("hdiutil", ["detach", montaje.path, "-quiet"]) }

        let origen = montaje.appendingPathComponent("SubFix.app")
        guard gestor.fileExists(atPath: origen.path) else {
            throw ErrorDeSubFix.fallóLaActualización("el DMG no trae SubFix.app")
        }
        let nueva = preparada.appendingPathComponent("SubFix.app")
        let copia = try Herramientas.correr("ditto", [origen.path, nueva.path])
        guard copia.codigo == 0 else { throw ErrorDeSubFix.fallóLaActualización("no se pudo copiar la app nueva") }

        try verificar(nueva: nueva, contra: instalada)
        if let version {
            let plist = NSDictionary(contentsOf: nueva.appendingPathComponent("Contents/Info.plist"))
            guard plist?["CFBundleShortVersionString"] as? String == version else {
                throw ErrorDeSubFix.fallóLaActualización("la app del DMG no es la versión \(version)")
            }
        }
        return nueva
    }

    /// La regla de firma («designated requirement») de la app: incluye el hash del certificado.
    static func reglaDeFirma(_ app: URL) -> String? {
        guard let salida = try? Herramientas.correr("codesign", ["-d", "-r-", app.path]) else { return nil }
        let todo = salida.texto + "\n" + salida.error
        return todo.split(separator: "\n").first { $0.hasPrefix("designated =>") }.map(String.init)
    }

    /// Firma íntegra y del mismo certificado que la app que está corriendo. Si faltara
    /// cualquiera de las dos, no se instala nada.
    public static func verificar(nueva: URL, contra instalada: URL) throws {
        let integra = try Herramientas.correr("codesign", ["--verify", "--deep", "--strict", nueva.path])
        guard integra.codigo == 0 else {
            throw ErrorDeSubFix.fallóLaActualización("la firma de la app nueva no es válida")
        }
        guard let reglaNueva = reglaDeFirma(nueva), let reglaVieja = reglaDeFirma(instalada),
              reglaNueva == reglaVieja else {
            throw ErrorDeSubFix.fallóLaActualización("la app nueva no está firmada con el mismo certificado que la instalada")
        }
    }

    // MARK: Instalar

    /// Pone la app nueva en `destino`. La vieja va a la Papelera (se puede recuperar) y, si algo
    /// falla a medias, se vuelve a dejar donde estaba.
    public static func instalar(_ nueva: URL, en destino: URL) throws {
        let gestor = FileManager.default
        var enPapelera: NSURL?
        if gestor.fileExists(atPath: destino.path) {
            try gestor.trashItem(at: destino, resultingItemURL: &enPapelera)
        }
        let copia = try Herramientas.correr("ditto", [nueva.path, destino.path])
        guard copia.codigo == 0 else {
            if let papelera = enPapelera as URL? { try? gestor.moveItem(at: papelera, to: destino) }
            throw ErrorDeSubFix.fallóLaActualización("no se pudo copiar a \(destino.path): \(copia.error)")
        }
        // Por si acaso: sin la marca de «descargado de internet», macOS no vuelve a pedir
        // «Abrir de todos modos». Es seguro porque arriba ya se comprobó hash y certificado.
        _ = try? Herramientas.correr("xattr", ["-dr", "com.apple.quarantine", destino.path])
    }

    /// Abre la app de nuevo cuando la actual ya se haya cerrado.
    public static func relanzar(_ app: URL) {
        let proceso = Process()
        proceso.executableURL = URL(fileURLWithPath: "/bin/sh")
        proceso.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", app.path]
        try? proceso.run()
    }
}
