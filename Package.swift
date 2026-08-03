// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SubFix",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SubFixKit", targets: ["SubFixKit"]),
        .library(name: "SubFixUI", targets: ["SubFixUI"]),
        .executable(name: "SubFix", targets: ["SubFix"]),
        .executable(name: "subfixtests", targets: ["subfixtests"]),
        .executable(name: "subfixshot", targets: ["subfixshot"]),
    ],
    targets: [
        // Motor: sondeo con ffprobe, extracción, formato para el TV y
        // OpenSubtitles. Sin nada de interfaz, para poder probarlo sin ventana.
        .target(name: "SubFixKit"),

        // Igual que en Bóveda: las vistas viven en una librería, no en el
        // ejecutable, porque las previews de SwiftUI no funcionan dentro de un
        // executableTarget.
        .target(name: "SubFixUI", dependencies: ["SubFixKit"]),

        .executableTarget(name: "SubFix", dependencies: ["SubFixUI"]),
        .executableTarget(name: "subfixtests", dependencies: ["SubFixKit", "SubFixUI"]),
        // Retratos de la interfaz a PNG, para revisarla sin permiso de captura.
        .executableTarget(name: "subfixshot", dependencies: ["SubFixUI"]),
    ]
)
