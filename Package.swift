// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SubFix",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SubFixKit", targets: ["SubFixKit"]),
        .library(name: "OrganizarKit", targets: ["OrganizarKit"]),
        .library(name: "SubFixUI", targets: ["SubFixUI"]),
        .executable(name: "SubFix", targets: ["SubFix"]),
        .executable(name: "subfixtests", targets: ["subfixtests"]),
        .executable(name: "subfixshot", targets: ["subfixshot"]),
    ],
    targets: [
        // Motor: sondeo con ffprobe, extracción, formato para el TV y
        // OpenSubtitles. Sin nada de interfaz, para poder probarlo sin ventana.
        .target(name: "SubFixKit"),

        // Lo que antes era la app Cartelera: lee el nombre de cada descarga y la
        // lleva a `Título (Año)` o `Serie/Season XX` para Jellyfin y Plex.
        .target(name: "OrganizarKit"),

        // Igual que en Bóveda: las vistas viven en una librería, no en el
        // ejecutable, porque las previews de SwiftUI no funcionan dentro de un
        // executableTarget.
        .target(name: "SubFixUI", dependencies: ["SubFixKit", "OrganizarKit"]),

        .executableTarget(name: "SubFix", dependencies: ["SubFixUI"]),
        .executableTarget(name: "subfixtests", dependencies: ["SubFixKit", "SubFixUI", "OrganizarKit"]),
        // Retratos de la interfaz a PNG, para revisarla sin permiso de captura.
        .executableTarget(name: "subfixshot", dependencies: ["SubFixUI"]),
    ]
)
