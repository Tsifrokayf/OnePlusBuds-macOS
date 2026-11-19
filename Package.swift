// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OnePlusBuds",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OnePlusBuds",
            path: "Sources/OnePlusBuds",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("WidgetKit")
            ]
        )
    ]
)
