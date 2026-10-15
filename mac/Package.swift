// swift-tools-version:6.2
import PackageDescription

// Builds with Command Line Tools only (no Xcode). See README.md.
// MoneybookCore and MoneybookClient are also used by the iPhone app (../ios).
let package = Package(
    name: "Moneybook",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .executable(name: "Moneybook", targets: ["Moneybook"]),
        .library(name: "MoneybookCore", targets: ["MoneybookCore"]),
        .library(name: "MoneybookClient", targets: ["MoneybookClient"]),
    ],
    targets: [
        // Pure, UI-free logic: models, sync merge, date periods, aggregation, money formatting.
        .target(name: "MoneybookCore"),
        // REST client for the Moneybook server.
        // Async calls run on the caller's actor, so callers can pass `[String: Any]` bodies.
        .target(name: "MoneybookClient", dependencies: ["MoneybookCore"],
                swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .executableTarget(
            name: "Moneybook",
            dependencies: ["MoneybookCore", "MoneybookClient"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "MoneybookCoreTests",
            dependencies: ["MoneybookCore"],
            // CLT keeps the swift-testing macro plugin in a subfolder the SDK 27 build doesn't search.
            swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]
        ),
    ]
)
