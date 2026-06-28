# StockWatchlist — iOS App Design Spec
> Version: 1.0.0 | Author: Calvin Lee | Date: 2026-06-07
> Purpose: Prototype/production-like iOS app for learning mobile development
> Data: Simulated only — NO real financial data, NO PII, NO API keys required

---

## App Concept

A personal stock watchlist app where the user tracks stocks they are **investing in** and **watching**.
All price data is simulated using a random walk algorithm — realistic movement without real market data.

---

## MobileDashboardKit Mapping

```
Container          → StockWatchlistApp (the whole app)
  Dashboard 1      → InvestingDashboard   (stocks you own)
  Dashboard 2      → WatchlistDashboard   (stocks you are monitoring)
  Dashboard 3      → PerformanceDashboard (portfolio summary)

Tile Types:
  StockPriceTile       ← current price + % change
  PortfolioValueTile   ← total value of holdings
  AlertTile            ← price crossed a threshold
  ChartTile            ← 7-day simulated price history
  SummaryTile          ← gain/loss summary
```

---

## Project Structure

```
StockWatchlist/
├── StockWatchlist.xcodeproj
└── StockWatchlist/
    ├── App/
    │   └── StockWatchlistApp.swift          ← @main entry point
    ├── Container/
    │   └── AppContainer.swift               ← root Container from MobileDashboardKit
    ├── Dashboards/
    │   ├── InvestingDashboard.swift          ← extends DashboardTemplate
    │   ├── WatchlistDashboard.swift          ← extends DashboardTemplate
    │   └── PerformanceDashboard.swift        ← extends DashboardTemplate
    ├── Tiles/
    │   ├── StockPriceTile.swift              ← extends TileTemplate
    │   ├── PortfolioValueTile.swift          ← extends TileTemplate
    │   ├── AlertTile.swift                   ← extends TileTemplate
    │   ├── ChartTile.swift                   ← extends TileTemplate
    │   └── SummaryTile.swift                 ← extends TileTemplate
    ├── Models/
    │   ├── Stock.swift                       ← ticker, name, sector
    │   ├── Holding.swift                     ← stock + quantity + avgCostBasis
    │   ├── PricePoint.swift                  ← timestamp + simulated price
    │   └── PriceAlert.swift                  ← alertPrice + direction (above/below)
    ├── Services/
    │   ├── SimulatedPriceFeed.swift          ← random walk price generator
    │   └── PortfolioCalculator.swift         ← gain/loss, total value
    ├── Views/
    │   ├── ContainerView.swift               ← root navigation
    │   ├── DashboardView.swift               ← renders a dashboard + its tiles
    │   ├── TileView.swift                    ← renders individual tile
    │   └── AddStockView.swift                ← form to add stock to list
    └── Preview Content/
        └── PreviewData.swift                 ← seed data for Xcode previews
```

---

## Data Models

### Stock.swift
```swift
import Foundation

struct Stock: Identifiable, Codable, Hashable {
    let id: UUID
    var ticker: String          // e.g. "AAPL"
    var companyName: String     // e.g. "Apple Inc."
    var sector: String          // e.g. "Technology"
    var currentPrice: Decimal   // simulated — never real market data
    var previousClose: Decimal  // simulated

    var priceChangePercent: Decimal {
        guard previousClose > 0 else { return 0 }
        return ((currentPrice - previousClose) / previousClose) * 100
    }

    var isGaining: Bool { currentPrice >= previousClose }
}
```

### Holding.swift
```swift
import Foundation

struct Holding: Identifiable, Codable {
    let id: UUID
    var stock: Stock
    var quantity: Decimal           // number of shares (synthetic)
    var averageCostBasis: Decimal   // average price paid per share (synthetic)

    var totalValue: Decimal { stock.currentPrice * quantity }
    var totalCost: Decimal { averageCostBasis * quantity }
    var unrealizedGainLoss: Decimal { totalValue - totalCost }
    var returnPercent: Decimal {
        guard totalCost > 0 else { return 0 }
        return (unrealizedGainLoss / totalCost) * 100
    }
}
```

### PricePoint.swift
```swift
import Foundation

struct PricePoint: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let price: Decimal
}
```

### PriceAlert.swift
```swift
import Foundation

enum AlertDirection: String, Codable {
    case above, below
}

struct PriceAlert: Identifiable, Codable {
    let id: UUID
    var ticker: String
    var alertPrice: Decimal
    var direction: AlertDirection
    var isTriggered: Bool = false
    var note: String
}
```

---

## Simulated Price Feed

```swift
// SimulatedPriceFeed.swift
// Random walk algorithm — realistic price movement, no real market data

import Foundation
import Combine

class SimulatedPriceFeed: ObservableObject {
    static let shared = SimulatedPriceFeed()

    @Published var prices: [String: Decimal] = [:]      // ticker → current price
    @Published var history: [String: [PricePoint]] = [:] // ticker → 7-day history

    private var timer: AnyCancellable?
    private let volatility: Double = 0.015               // 1.5% max move per tick

    func start(tickers: [String], seedPrices: [String: Decimal]) {
        prices = seedPrices
        generateHistory(tickers: tickers, seedPrices: seedPrices)

        // Update prices every 5 seconds
        timer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick(tickers: tickers)
            }
    }

    func stop() { timer?.cancel() }

    private func tick(tickers: [String]) {
        for ticker in tickers {
            guard let current = prices[ticker] else { continue }
            let change = Double.random(in: -volatility...volatility)
            let newPrice = Decimal(Double(truncating: current as NSNumber) * (1 + change))
            prices[ticker] = max(newPrice, 1.00)  // floor at $1.00
        }
    }

    private func generateHistory(tickers: [String], seedPrices: [String: Decimal]) {
        let calendar = Calendar.current
        let now = Date()

        for ticker in tickers {
            guard var price = seedPrices[ticker] else { continue }
            var points: [PricePoint] = []

            for dayOffset in (0..<7).reversed() {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
                let change = Double.random(in: -volatility...volatility)
                price = max(Decimal(Double(truncating: price as NSNumber) * (1 + change)), 1.00)
                points.append(PricePoint(id: UUID(), timestamp: date, price: price))
            }
            history[ticker] = points
        }
    }
}
```

---

## Seed Data (No Real Financial Data)

```swift
// PreviewData.swift — synthetic stocks for previews and dev testing

extension Stock {
    static let seedStocks: [Stock] = [
        Stock(id: UUID(), ticker: "AAPL", companyName: "Apple Inc.", sector: "Technology",
              currentPrice: 182.50, previousClose: 180.00),
        Stock(id: UUID(), ticker: "MSFT", companyName: "Microsoft Corp.", sector: "Technology",
              currentPrice: 415.20, previousClose: 420.00),
        Stock(id: UUID(), ticker: "GOOGL", companyName: "Alphabet Inc.", sector: "Technology",
              currentPrice: 175.80, previousClose: 173.00),
        Stock(id: UUID(), ticker: "JPM", companyName: "JPMorgan Chase", sector: "Financial",
              currentPrice: 198.40, previousClose: 195.00),
        Stock(id: UUID(), ticker: "NVDA", companyName: "NVIDIA Corp.", sector: "Semiconductors",
              currentPrice: 875.30, previousClose: 890.00),
    ]
}

// Seed prices for SimulatedPriceFeed
let seedPrices: [String: Decimal] = [
    "AAPL": 182.50,
    "MSFT": 415.20,
    "GOOGL": 175.80,
    "JPM": 198.40,
    "NVDA": 875.30,
]
```

---

## Dashboard Definitions

### InvestingDashboard (stocks you own)
```swift
class InvestingDashboard: DashboardTemplate {
    var holdings: [Holding]

    init(holdings: [Holding]) {
        self.holdings = holdings
        let tiles: [TileTemplate] = [
            PortfolioValueTile(holdings: holdings),
            SummaryTile(holdings: holdings)
        ] + holdings.map { StockPriceTile(holding: $0) }

        super.init(name: "My Investments", tiles: tiles)
    }
}
```

### WatchlistDashboard (stocks you monitor)
```swift
class WatchlistDashboard: DashboardTemplate {
    var watchedStocks: [Stock]
    var alerts: [PriceAlert]

    init(stocks: [Stock], alerts: [PriceAlert]) {
        self.watchedStocks = stocks
        self.alerts = alerts
        let tiles: [TileTemplate] =
            stocks.map { StockPriceTile(stock: $0) } +
            alerts.map { AlertTile(alert: $0) }

        super.init(name: "Watchlist", tiles: tiles)
    }
}
```

### PerformanceDashboard (charts + summary)
```swift
class PerformanceDashboard: DashboardTemplate {
    init(holdings: [Holding]) {
        let tiles: [TileTemplate] = holdings.map {
            ChartTile(ticker: $0.stock.ticker)
        }
        super.init(name: "Performance", tiles: tiles)
    }
}
```

---

## Screens / Navigation Flow

```
TabView
  ├── Tab 1: Investments    → InvestingDashboard view
  ├── Tab 2: Watchlist      → WatchlistDashboard view
  ├── Tab 3: Performance    → PerformanceDashboard view (charts)
  └── Tab 4: Settings       → Manage stocks, alerts, reset data
```

---

## Learning Milestones

| Milestone | What You Learn |
|---|---|
| 1. Display seed stock list | SwiftUI List, NavigationStack |
| 2. Add/remove stocks | SwiftData CRUD, @Query |
| 3. Live price updates | Combine, @Published, Timer |
| 4. Charts | Swift Charts framework |
| 5. Price alerts | Background logic, conditional UI |
| 6. MobileDashboardKit integration | Swift Package Manager, local dependency |

---

## Design Rules

| Rule | Detail |
|---|---|
| All prices | `Decimal` — never `Double` or `Float` |
| All data | Synthetic only — no real market APIs |
| No PII | No user accounts, no real names |
| Persistence | SwiftData (local device only) |
| Min platform | iOS 17+ |
| Architecture | MVVM — Views observe `@ObservableObject` |

---

## Prompt for Claude / Xcode Intelligence

> Use this prompt when starting implementation inside the StockWatchlist Xcode project:

```
Create an iOS SwiftUI application named StockWatchlist using the design in StockWatchlist_App_Design.md.

Requirements:
1. Target iOS 17+ using SwiftUI and SwiftData
2. Import MobileDashboardKit as a local Swift Package dependency
3. Three dashboards: InvestingDashboard, WatchlistDashboard, PerformanceDashboard
4. Five tile types: StockPriceTile, PortfolioValueTile, AlertTile, ChartTile, SummaryTile
5. All price data is simulated using SimulatedPriceFeed (random walk — no real APIs)
6. All monetary values use Decimal — never Double or Float
7. Use Swift Charts for the ChartTile 7-day price history
8. Navigation via TabView with 4 tabs: Investments, Watchlist, Performance, Settings
9. Seed data from PreviewData.swift — 5 synthetic stocks (AAPL, MSFT, GOOGL, JPM, NVDA)
10. Persist holdings and watchlist using SwiftData (local only)
11. Follow MVVM architecture — Views observe ObservableObject view models
12. No PII, no real financial data, no API keys

Follow the exact project structure and data models defined in StockWatchlist_App_Design.md.
```

---

## Companion Files

| File | Purpose |
|---|---|
| `MobileDashboardKit_Design.md` | Reusable package design — build this first |
| `StockWatchlist_App_Design.md` | This file — iOS app that consumes the package |

## Build Order

```
Step 1 → Create MobileDashboardKit Swift Package (library)
Step 2 → Create StockWatchlist Xcode Project (app)
Step 3 → Add MobileDashboardKit as local package dependency in StockWatchlist
Step 4 → Implement models, services, dashboards, tiles
Step 5 → Wire up TabView navigation and SwiftData persistence
```

---

*File*: `StockWatchlist_App_Design.md`
*Location*: `~/ai_workspace_local/claude_context_engineering/`
*Next step*: Build MobileDashboardKit package first, then create the StockWatchlist Xcode project.
