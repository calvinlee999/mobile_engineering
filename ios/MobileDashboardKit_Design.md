# MobileDashboardKit — Swift Package Design Spec
> Version: 1.0.0 | Author: Calvin Lee | Date: 2026-06-07
> Purpose: Reusable Swift library/framework for generic mobile native applications

---

## Overview

A Swift Package (`MobileDashboardKit`) that provides a generic, extensible dashboard framework.
Consumer apps inherit from the base templates to build their own dashboards and tiles.

---

## Data Model Relationships

```
Container (1)
  └── Dashboard (many)          ← extends DashboardTemplate
        └── Tile (many)         ← extends TileTemplate

DashboardTemplate  ← base class — all dashboards inherit from this
TileTemplate       ← base class — all tiles inherit from this
```

---

## Package Structure

```
MobileDashboardKit/
├── Package.swift
└── Sources/
    └── MobileDashboardKit/
        ├── Container/
        │   └── Container.swift
        ├── Dashboard/
        │   ├── DashboardTemplate.swift      ← generic base
        │   └── Dashboard.swift              ← concrete default implementation
        ├── Tile/
        │   ├── TileTemplate.swift           ← generic base
        │   └── Tile.swift                   ← concrete default implementation
        └── MobileDashboardKit.swift         ← public API surface
```

---

## Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MobileDashboardKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MobileDashboardKit",
            targets: ["MobileDashboardKit"]
        )
    ],
    targets: [
        .target(
            name: "MobileDashboardKit",
            path: "Sources/MobileDashboardKit"
        ),
        .testTarget(
            name: "MobileDashboardKitTests",
            dependencies: ["MobileDashboardKit"]
        )
    ]
)
```

---

## Core Classes

### TileTemplate.swift

```swift
import SwiftUI

/// Base class for all tiles. Subclass this to create custom tiles.
open class TileTemplate: Identifiable, ObservableObject {
    public let id: UUID
    public var title: String
    public var isVisible: Bool

    public init(id: UUID = UUID(), title: String, isVisible: Bool = true) {
        self.id = id
        self.title = title
        self.isVisible = isVisible
    }

    /// Override in subclass to provide custom SwiftUI view
    open func render() -> AnyView {
        AnyView(EmptyView())
    }
}
```

### DashboardTemplate.swift

```swift
import SwiftUI

/// Base class for all dashboards. Subclass this to create custom dashboards.
open class DashboardTemplate: Identifiable, ObservableObject {
    public let id: UUID
    public var name: String
    @Published public var tiles: [TileTemplate]

    public init(id: UUID = UUID(), name: String, tiles: [TileTemplate] = []) {
        self.id = id
        self.name = name
        self.tiles = tiles
    }

    public func addTile(_ tile: TileTemplate) {
        tiles.append(tile)
    }

    public func removeTile(id: UUID) {
        tiles.removeAll { $0.id == id }
    }

    public func tile(by id: UUID) -> TileTemplate? {
        tiles.first { $0.id == id }
    }
}
```

### Container.swift

```swift
import SwiftUI

/// Top-level container. Holds one or many dashboards.
public class Container: Identifiable, ObservableObject {
    public let id: UUID
    public var name: String
    @Published public var dashboards: [DashboardTemplate]

    public init(id: UUID = UUID(), name: String, dashboards: [DashboardTemplate] = []) {
        self.id = id
        self.name = name
        self.dashboards = dashboards
    }

    public func addDashboard(_ dashboard: DashboardTemplate) {
        dashboards.append(dashboard)
    }

    public func removeDashboard(id: UUID) {
        dashboards.removeAll { $0.id == id }
    }

    public func dashboard(by id: UUID) -> DashboardTemplate? {
        dashboards.first { $0.id == id }
    }
}
```

### MobileDashboardKit.swift (Public API Surface)

```swift
/// MobileDashboardKit — Public re-exports
@_exported import class MobileDashboardKit.Container
@_exported import class MobileDashboardKit.DashboardTemplate
@_exported import class MobileDashboardKit.TileTemplate
```

---

## Extension Pattern (Consumer App Usage)

```swift
// In your app — extend TileTemplate for custom tile types
class ChartTile: TileTemplate {
    var chartData: [Double]

    init(title: String, chartData: [Double]) {
        self.chartData = chartData
        super.init(title: title)
    }

    override func render() -> AnyView {
        AnyView(Text("Chart: \(chartData.count) points"))
    }
}

// In your app — extend DashboardTemplate for custom dashboards
class AnalyticsDashboard: DashboardTemplate {
    var refreshInterval: TimeInterval

    init(name: String, refreshInterval: TimeInterval = 30) {
        self.refreshInterval = refreshInterval
        super.init(name: name)
    }
}

// Wiring it together
let container = Container(name: "Main App")
let dashboard = AnalyticsDashboard(name: "Analytics", refreshInterval: 60)
let tile = ChartTile(title: "Revenue", chartData: [100, 200, 150])

dashboard.addTile(tile)
container.addDashboard(dashboard)
```

---

## Design Rules

| Rule | Detail |
|---|---|
| Base classes use `open` | Allows subclassing from other modules |
| IDs are `UUID` | Stable, collision-free identity |
| Published collections | `@Published` on `tiles` and `dashboards` for SwiftUI reactivity |
| Monetary values | Use `Decimal` not `Double` if tiles display financial data |
| Platforms | iOS 17+ and macOS 14+ (SwiftUI + SwiftData era) |
| Thread safety | All `@Published` mutations must happen on `@MainActor` in production |

---

## Prompt for Claude / Xcode Intelligence

> Use this prompt when starting the implementation inside Xcode:

```
Create a Swift Package named MobileDashboardKit using the design in this file.

Requirements:
1. Package targets iOS 17+ and macOS 14+
2. Container holds one-to-many DashboardTemplate instances
3. DashboardTemplate holds one-to-many TileTemplate instances
4. DashboardTemplate and TileTemplate are open base classes (subclassable from consumer apps)
5. All collections use @Published for SwiftUI reactivity
6. Every class conforms to Identifiable using UUID
7. Include add/remove/find methods on Container and DashboardTemplate
8. Public API is clean — only expose what consumers need
9. Include a default concrete Dashboard and Tile subclass as usage examples
10. Add a test target with basic unit tests for add/remove operations

Follow the exact package structure and class signatures defined in MobileDashboardKit_Design.md.
```

---

*File*: `MobileDashboardKit_Design.md`
*Location*: `~/ai_workspace_local/claude_context_engineering/`
*Next step*: Create the Swift Package in Xcode (File → New → Package), then paste the prompt above into Claude/Xcode Intelligence.
