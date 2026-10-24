// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TableWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TableWorkbench", targets: ["TableWorkbenchApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/duckdb/duckdb-swift", exact: "1.1.3"),
        .package(url: "https://github.com/CoreOffice/CoreXLSX", from: "0.14.2"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20")
    ],
    targets: [
        .target(
            name: "DuckDBKit",
            dependencies: [
                .product(name: "DuckDB", package: "duckdb-swift"),
                .product(name: "CoreXLSX", package: "CoreXLSX"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        ),
        .target(name: "DataGrid", dependencies: ["DuckDBKit"]),
        .target(name: "ChartUI", dependencies: ["DuckDBKit"]),
        .target(name: "Features", dependencies: ["DuckDBKit"]),
        .executableTarget(
            name: "TableWorkbenchApp",
            dependencies: ["Features", "DataGrid", "DuckDBKit", "ChartUI"]
        ),
        .executableTarget(
            name: "TableWorkbenchBench",
            dependencies: ["Features", "DuckDBKit"]
        ),
        .executableTarget(
            name: "TableWorkbenchScrollBench",
            dependencies: ["Features", "DataGrid", "DuckDBKit"]
        ),
        .executableTarget(
            name: "TableWorkbenchSnapshot",
            dependencies: ["ChartUI", "DuckDBKit"]
        ),
        .executableTarget(
            name: "TableWorkbenchTests",
            dependencies: ["DuckDBKit", "Features", "DataGrid"]
        )
    ],
    swiftLanguageModes: [.v5]
)
