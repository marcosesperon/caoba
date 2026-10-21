// swift-tools-version: 6.0
// Paquete del motor de CAOBA: todo el procesado de imagen, vídeo y metadatos
// vive aquí, sin ninguna dependencia de interfaz. Lo comparten la app de macOS
// y la de iOS, y se puede probar con `swift test` sin abrir Xcode.
import PackageDescription

let package = Package(
    name: "CaobaCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "CaobaCore", targets: ["CaobaCore"]),
    ],
    targets: [
        .target(
            name: "CaobaCore",
            path: "Sources/CaobaCore",
            resources: [
                // Plantillas de collage exportadas de la app antigua (ver docs).
                .process("Collage/templates.json"),
                .process("Collage/carousel_templates.json"),
            ]
        ),
        .testTarget(
            name: "CaobaCoreTests",
            dependencies: ["CaobaCore"],
            path: "Tests/CaobaCoreTests"
        ),
    ]
)
