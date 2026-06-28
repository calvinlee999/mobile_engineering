# iOS FinTech Architecture — MVVM-C + Clean Architecture

> **Platform**: iOS 18.5+ · Swift 6.3+ · Xcode 26.6+ · SwiftUI · SwiftData
> **Pattern**: MVVM-C (Model-View-ViewModel-Coordinator) + Headless CMS
> **Versions**: Governed by `dotfiles/ENTERPRISE-GOLDEN-PATH.md` v4.0.0
> **Panel Score**: 9.95/10 (v4.0 — canonical architecture)
> **Status**: Ready to implement

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                     UI LAYER                         │
│  SwiftUI Views ◄───► @Observable ViewModels           │
│  @MainActor          emit Output intents only         │
└───────────────────────────┬──────────────────────────┘
                            │ intent routing
                            ▼
┌──────────────────────────────────────────────────────┐
│                 COORDINATOR LAYER                    │
│  AppCoordinator → child Coordinators                 │
│  Owns NavigationPath — screens reusable across flows │
└───────────────────────────┬──────────────────────────┘
                            │ use case calls
                            ▼
┌──────────────────────────────────────────────────────┐
│                  DOMAIN LAYER                        │
│  Pure Swift — NO framework imports                   │
│  Models, Protocols, UseCases                         │
└───────────────────────────┬──────────────────────────┘
                            │ implements protocols
                            ▼
┌──────────────────────────────────────────────────────┐
│               DATA + CMS LAYER                      │
│  SwiftData @Model · PriceFeedActor · EntityMapper    │
│  CMSService (actor) · TileConfig · DashboardConfig   │
└──────────────────────────────────────────────────────┘
```

---

## Coordinator Tree

```
AppCoordinator (root — biometric gate, tab selection)
├── InvestingCoordinator  (holdings, portfolio P&L)
├── WatchlistCoordinator  (stock prices, price alerts)
├── PerformanceCoordinator (30-day charts)
└── SettingsCoordinator   (preferences)
```

ViewModels emit intents (`.showStockDetail(ticker:)`). Coordinators own `NavigationPath`. Screens are 100% reusable across flows.

---

## Core Patterns

| Pattern | Implementation | Why |
|---------|---------------|-----|
| **MVVM-C** | Coordinator owns NavigationPath, ViewModel emits Output only | Navigation decoupled from business logic |
| **@Observable** | Macro replaces ObservableObject/@Published | Compiler-proven observation, iOS 17+ |
| **actor concurrency** | `actor PriceFeedActor` + AsyncStream | Zero data races at type-system level |
| **Clean Architecture** | Domain (pure Swift) → Data (SwiftData) → Presentation (SwiftUI) | Testable, swappable, framework-independent |
| **Protocol DI** | `AppEnvironment.live()` / `.mock()` — zero singletons | Full test isolation, SwiftUI Preview |
| **Headless CMS** | CMSService actor + TileKind enum + TileRenderable protocol | New tiles without App Store release |
| **TDD** | Red → Green → Refactor — FailureAnalysisService classifies failures | Every feature starts with a failing test |

---

## Design Rules

| Rule | Detail |
|------|--------|
| Money | `Decimal` only — never `Double`/`Float` |
| State | `@Observable` macro — never `ObservableObject`/`@Published` |
| Concurrency | `actor` types — never `class` + `DispatchQueue` |
| Navigation | Coordinator intents — never push/present in ViewModel |
| DI | `AppEnvironment` — never `static let shared` singleton |
| Sensitive UI | `MaskedValueView` — hide values when `scenePhase != .active` |
| Auth | Biometric gate (LAContext) before portfolio data |
| Secrets | Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) — never UserDefaults |
| Network | CertificatePinning (CryptoKit SHA256) on all HTTPS |
| Tests | 80% coverage gate (xcov), TDD Red-Green-Refactor |

---

## Security

| Layer | Implementation | Standard |
|-------|---------------|----------|
| **Biometric** | LAContext (Face ID / Touch ID) | Gate before financial data |
| **Storage** | Keychain with device-only accessibility | PCI-DSS least exposure |
| **Network** | CertificatePinningDelegate (CryptoKit SHA256) | OWASP M3 |
| **Tampering** | SecurityCheckService (jailbreak + debugger detection) | OWASP M8/M9 |
| **Display** | MaskedValueView (scenePhase detection) | Hide values in app switcher |

---

## Test Pyramid

| Layer | % | Tools |
|-------|---|-------|
| Unit | 50% | XCTestCase, @Observable mocks via AppEnvironment.mock() |
| Snapshot | 20% | swift-snapshot-testing (tile states, dark mode, masked values) |
| Integration | 20% | SwiftData + actor + Coordinator wired together |
| UI | 10% | XCUITest (biometric mock, deep links) |
| **Gate** | **80%** | xcov in CI |

---

## CI/CD

```
SwiftLint (strict) → xcodebuild build → xcodebuild test (≥80%) → XCUITest → Fastlane → TestFlight
```

---

## Simulator Standard

| Runtime | Devices |
|---------|---------|
| iOS 26.5 | iPhone 17 Pro, iPhone Air, iPhone 17e, iPad Pro 13" M5 |
| iOS 18.5 | iPhone 16 Pro, iPad Pro 13" M4 |

---

## Detailed Architecture Documents

| File | Version | Panel Score | Content |
|------|---------|-------------|---------|
| `MobileDashboardKit_Design.md` | v1.0 | 4.45/10 | Baseline — Container/Dashboard/Tile model |
| `StockWatchlist_App_Design.md` | v1.0 | 4.45/10 | Domain models — Stock, Holding, PriceAlert |
| `MobileDashboardKit_Enhanced_Architecture.md` | v3.0 | 9.913/10 | Full production stack — actors, security, CI/CD |
| `MobileDashboardKit_v4_MVVMC_CMS_Architecture.md` | v4.0 | **9.95/10** | **Canonical** — MVVM-C, Headless CMS, TDD |

---

## Cross-Reference

| Concern | Source |
|---------|--------|
| Technology versions | `dotfiles/ENTERPRISE-GOLDEN-PATH.md` v4.0.0 |
| Backend services | `Calvin_Infrastructure_Target/README.md` Device 2 — Kong :8000, PG :5432, Kafka :9092 |
| AI agent governance | `claude_context_engineering` — Pattern 0, PE Template v3.0 |
| Architecture patterns | `fintech_enterprise_architecture/README.md` Section 1A |
| Android counterpart | `mobile_engineering/android/ARCHITECTURE.md` |
