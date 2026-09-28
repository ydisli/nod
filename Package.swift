// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nod",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Nod", targets: ["Nod"]),
    ],
    targets: [
        // Pure logic: filters, the pointer engine, head gesture, click key and
        // dwell state machines. No AppKit, fully unit tested.
        .target(name: "NodCore"),

        // The menu bar app: AirPods motion, event posting and all UI.
        .executableTarget(
            name: "Nod",
            dependencies: ["NodCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("ServiceManagement"),
            ]
        ),

        .testTarget(name: "NodCoreTests", dependencies: ["NodCore"]),
    ]
)
