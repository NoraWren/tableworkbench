// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TableWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TableWorkbench", targets: ["TableWorkbenchApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/duckdb/duckdb-swift", exact: "1.1.3")
    ],
    targets: [
        .target(
            name: "DuckDBKit",
            dependencies: [.product(name: "DuckDB", package: "duckdb-swift")]
        ),
        .target(name: "DataGrid", dependencies: ["DuckDBKit"]),
        .target(name: "Features", dependencies: ["DuckDBKit"]),
        .executableTarget(
            name: "TableWorkbenchApp",
            dependencies: ["Features", "DataGrid", "DuckDBKit"]
        ),
        .executableTarget(
            name: "TableWorkbenchBench",
            dependencies: ["Features", "DuckDBKit"]
        ),
        .executableTarget(
            name: "TableWorkbenchTests",
            dependencies: ["DuckDBKit", "Features", "DataGrid"]
        )
    ],
    swiftLanguageModes: [.v5]
)
