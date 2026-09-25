// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nod",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Nod", targets: ["Nod"]),
    ],
    targets: [
        // Pure logic: filters, calibration maths, gesture and dwell state machines,
        // face geometry. No AppKit, no camera, fully unit tested.
        .target(name: "NodCore"),

        // The menu bar app: camera, Vision, event posting and all UI.
        .executableTarget(
            name: "Nod",
            dependencies: ["NodCore"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),

        .testTarget(name: "NodCoreTests", dependencies: ["NodCore"]),
    ]
)
