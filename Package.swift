// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VV00P",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "VV00PCore", targets: ["VV00PCore"]),
    ],
    dependencies: [
        .package(path: "../src/Asherlc__whoop-ble-swift"),
    ],
    targets: [
        // Compiles the iOS app sources on this Mac so the session and screen typecheck
        // without an iOS simulator. The Xcode app target is what runs on the phone.
        .target(
            name: "SessionCompile",
            dependencies: [
                "VV00PCore",
                .product(name: "WhoopBLE", package: "Asherlc__whoop-ble-swift"),
            ],
            path: "App",
            exclude: ["VV00PApp.swift", "Fonts", "OpenRouter.plist", "OpenRouter.example.plist"]
        ),
        .target(
            name: "VV00PCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "pace-check",
            dependencies: ["VV00PCore"]
        ),
    ]
)
