import Foundation
import SubFixKit

/// Las pruebas de la actualización desde GitHub. La de red (baja de verdad la Release
/// publicada e instala en una carpeta temporal) sólo corre con SUBFIX_PROBAR_RED=1.
func pruebasDeActualizar() async {
    print("\n▸ ACTUALIZAR DESDE GITHUB")
    probar("versiones: 1.10.0 es más nueva que 1.9.3, y v1.6.0 no lo es que 1.6") {
        Actualizador.esMasNueva("1.10.0", que: "1.9.3") && !Actualizador.esMasNueva("v1.6.0", que: "1.6")
            && Actualizador.esMasNueva("v1.6.1", que: "1.6.0") && !Actualizador.esMasNueva("1.5.9", que: "1.6.0")
    }
    let respuesta = """
    {"tag_name":"v1.7.0","body":"Novedades","html_url":"https://github.com/x/y/releases/tag/v1.7.0",
     "draft":false,"prerelease":false,
     "assets":[{"name":"SubFix-1.7.0.dmg","browser_download_url":"https://github.com/x/y/a.dmg",
                "digest":"sha256:ABCDEF"}]}
    """
    probar("lee la Release: versión, DMG y hash de GitHub") {
        let v = try Actualizador.interpretar(Data(respuesta.utf8), actual: "1.6.0")
        return v?.version == "1.7.0" && v?.sha256 == "abcdef" && v?.urlDMG.lastPathComponent == "a.dmg"
    }
    probar("si ya la tengo, no avisa") {
        try Actualizador.interpretar(Data(respuesta.utf8), actual: "1.7.0") == nil
    }
    probar("una prerelease no se ofrece") {
        let pre = respuesta.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true")
        return try Actualizador.interpretar(Data(pre.utf8), actual: "1.6.0") == nil
    }

    let instalada = URL(fileURLWithPath: "/Applications/SubFix.app")
    guard FileManager.default.fileExists(atPath: instalada.path) else { return }
    let temporal = FileManager.default.temporaryDirectory.appendingPathComponent("subfix-act-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: temporal, withIntermediateDirectories: true)

    probar("una app firmada con OTRO certificado se rechaza") {
        let ajena = temporal.appendingPathComponent("Ajena.app")
        _ = try Herramientas.correr("ditto", [instalada.path, ajena.path])
        _ = try Herramientas.correr("codesign", ["--force", "--deep", "--sign", "-", ajena.path])   // ad-hoc
        do { try Actualizador.verificar(nueva: ajena, contra: instalada); return false } catch {
            return error.localizedDescription.contains("mismo certificado")
        }
    }

    guard ProcessInfo.processInfo.environment["SUBFIX_PROBAR_RED"] == "1" else {
        print("  ⏭  sin SUBFIX_PROBAR_RED=1: se omite la descarga real de GitHub")
        return
    }
    await probarEsperando("de punta a punta: baja la Release real, comprueba hash y firma, instala sin cuarentena") {
        guard let v = try await Actualizador.buscar(actual: "1.0.0") else { return false }
        let dmg = try await Actualizador.descargar(v) { _ in }
        let nueva = try Actualizador.prepararEnTemporal(dmg: dmg, esperando: v.version, comparandoCon: instalada)
        let destino = temporal.appendingPathComponent("SubFix.app")
        try Actualizador.instalar(nueva, en: destino)
        let firma = try Herramientas.correr("codesign", ["--verify", "--deep", "--strict", destino.path])
        let cuarentena = try Herramientas.correr("xattr", ["-p", "com.apple.quarantine", destino.path])
        print("       instaló la \(v.version) (hash \(v.sha256 == nil ? "sin publicar" : "comprobado"))")
        return v.sha256 != nil && firma.codigo == 0 && cuarentena.codigo != 0
    }
}
