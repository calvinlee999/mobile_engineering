# Mobile Engineering — FinTech 3-Platform Architecture

> **Owner**: Calvin Lee — Principal Platform Engineering
> **iOS**: iOS 18.5+ · Swift 6.3+ · Xcode 26.6+ · MVVM-C + Clean Architecture (9.95/10)
> **Android**: API 26+ · Kotlin · Jetpack Compose · MVVM + Clean Architecture (Google recommended)
> **Web**: React / Next.js · TypeScript 6.x · Node 22 LTS (NVM) — see `fintech_enterprise_architecture`
> **Versions**: `dotfiles/ENTERPRISE-GOLDEN-PATH.md` v4.0.0
> **Last updated**: 2026-06-28

---

## Repository Structure

```
mobile_engineering/
├── ios/                              ← iOS architecture (Swift/SwiftUI)
│   ├── ARCHITECTURE.md                  Concise reference — patterns, rules, security, tests
│   ├── MobileDashboardKit_v4_MVVMC_CMS_Architecture.md   Canonical (9.95/10)
│   ├── MobileDashboardKit_Enhanced_Architecture.md        v3.0 (9.913/10)
│   ├── MobileDashboardKit_Design.md                       v1.0 baseline
│   └── StockWatchlist_App_Design.md                       Domain models
│
├── android/                          ← Android architecture (Kotlin/Compose)
│   └── ARCHITECTURE.md                  MVVM + Clean Architecture, Hilt, Room, Coroutines
│
├── .github/copilot-instructions.md   ← AI agent governance
└── README.md                         ← This file
```

---

## Architecture Comparison

Both platforms follow the same layered pattern — only the framework implementations differ.

| Layer | iOS (Swift/SwiftUI) | Android (Kotlin/Compose) |
|-------|--------------------|-----------------------|
| **Pattern** | MVVM-C (Coordinator owns navigation) | MVVM (ViewModel + Navigation Component) |
| **UI** | SwiftUI (declarative) | Jetpack Compose (declarative) |
| **State** | `@Observable` macro + StateFlow | `StateFlow` + sealed `UiState` |
| **Concurrency** | Swift `actor` + `async/await` | Kotlin Coroutines + `Flow` |
| **DI** | AppEnvironment (`live()` / `mock()`) | Hilt (`@Inject`, `@HiltViewModel`) |
| **Local DB** | SwiftData (`@Model`) | Room (`@Entity`, `@Dao`) |
| **Network** | URLSession + CryptoKit cert pinning | Retrofit + OkHttp cert pinning |
| **Biometric** | LAContext (Face ID / Touch ID) | BiometricPrompt (AndroidX) |
| **Secure storage** | Keychain | EncryptedSharedPreferences |
| **CI/CD** | SwiftLint → xcodebuild → xcov → Fastlane → TestFlight | ktlint → Gradle → JaCoCo → Play Console |

---

## Shared Standards (Both Platforms)

| Standard | Rule |
|----------|------|
| **Monetary values** | `Decimal` (iOS) / `BigDecimal` (Android) — NEVER floating-point |
| **Coverage gate** | 80% minimum (xcov / JaCoCo) |
| **API gateway** | Kong Gateway `:8000` → Spring Boot microservices |
| **API contract** | OpenAPI 3.1 (shared spec, generated typed clients) |
| **Biometric** | Gate before any financial data access |
| **Certificate pinning** | All HTTPS endpoints — OWASP M3 |
| **Offline-first** | Local DB as source of truth, network refresh |
| **Test pyramid** | Unit 50% · Snapshot 20% · Integration 20% · UI 10% |
| **TDD** | Red → Green → Refactor — no feature without a test |

---

## Backend Connectivity

Both platforms connect to the same backend through Kong Gateway.

| Environment | URL | Backend |
|-------------|-----|---------|
| **Dev** (Mac Mini) | `http://192.168.68.20:8000` | Kong → Spring Boot → PostgreSQL / Redis / Kafka |
| **Prod** (AWS) | `https://api.{domain}.com` | Kong (ECS/EKS) → Spring Boot → RDS / ElastiCache / MSK |

Same `kong.yml` routes, same Spring Boot code, same Kafka topics — dev mirrors prod.

---

## Calvin Enterprise Development Reference Group

| Repo | Provides to Mobile |
|------|--------------------|
| [`dotfiles`](https://github.com/calvinlee999/dotfiles) | `ENTERPRISE-GOLDEN-PATH.md` — Xcode 26.6, Android Studio latest, Node 22 LTS, all version pins |
| [`Calvin_Infrastructure_Target`](https://github.com/calvinlee999/Calvin_Infrastructure_Target) | Backend services inventory — Kong :8000, PostgreSQL :5432, Redis :6379, Kafka :9092, Grafana :3000 |
| [`claude_context_engineering`](https://github.com/calvinlee999/claude_context_engineering) | Pattern 0 operating model, PE Template v3.0, 12-Dimension CE Framework |
| [`fintech_enterprise_architecture`](https://github.com/calvinlee999/fintech_enterprise_architecture) | 76 enterprise patterns — Section 1: 14 mobile patterns (6 iOS + 8 Android), cross-platform comparison |
| [`Calvin_Investment_Framework`](https://github.com/calvinlee999/Calvin_Investment_Framework) | CIF v9.8 — investment methodology, portfolio domain models, decision architecture |
| **[`mobile_engineering`](https://github.com/calvinlee999/mobile_engineering)** (this repo) | iOS MVVM-C (9.95/10) + Android MVVM architecture, ready to implement |

---

**Maintained by**: Calvin Lee — Principal Platform Engineering
**Version**: 2.0.0 | 2026-06-28
