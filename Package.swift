// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SANIVA",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SANIVA", targets: ["SANIVA"]),
        .executable(name: "saniva-scan", targets: ["SANIVACLI"])
    ],
    targets: [
        .target(name: "SANIVACore", path: "Sources/SANIVACore"),
        .executableTarget(
            name: "SANIVA",
            dependencies: ["SANIVACore"],
            path: "Sources/SpaceSentry"
        ),
        .executableTarget(name: "SANIVACLI", dependencies: ["SANIVACore"], path: "Sources/SANIVACLI")
    ]
)
