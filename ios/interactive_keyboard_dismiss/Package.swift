// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "interactive_keyboard_dismiss",
    platforms: [
        .iOS("13.0"),
    ],
    products: [
        .library(name: "interactive-keyboard-dismiss", targets: ["interactive_keyboard_dismiss"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "interactive_keyboard_dismiss",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)
