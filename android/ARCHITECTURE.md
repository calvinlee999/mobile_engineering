# Android FinTech Architecture — MVVM + Clean Architecture

> **Platform**: API 26+ · Kotlin · Jetpack Compose · MVVM + Clean Architecture
> **Standard**: Google official architecture recommendation
> **Versions**: Governed by `dotfiles/ENTERPRISE-GOLDEN-PATH.md` v4.0.0
> **Patterns**: See `fintech_enterprise_architecture/README.md` Section 1B for full detail
> **Status**: Ready to implement

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                     UI LAYER                         │
│  Jetpack Compose ◄───► ViewModel (StateFlow)         │
│  @Composable screens    @HiltViewModel               │
└───────────────────────────┬──────────────────────────┘
                            │ UI State ↑ / User Events ↓
                            ▼
┌──────────────────────────────────────────────────────┐
│                  DOMAIN LAYER                        │
│  UseCases — pure Kotlin, no Android imports          │
│  Business rules, validation, data transformation     │
└───────────────────────────┬──────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────┐
│                    DATA LAYER                        │
│  Repository (single source of truth)                 │
│  ├── Local: Room DB (@Entity, @Dao)                  │
│  └── Remote: Retrofit + OkHttp → Kong Gateway        │
└──────────────────────────────────────────────────────┘
```

---

## Module Structure

```
:app                    Application entry, Hilt setup, Navigation host
:core:data              Repository impl, Room DB, Retrofit services
:core:domain            UseCases, domain models, repository interfaces (pure Kotlin)
:core:ui                Design system, shared Compose components, theme tokens
:core:network           OkHttp client, certificate pinning, interceptors
:core:security          BiometricPrompt, EncryptedSharedPreferences
:feature:portfolio      Investing dashboard — holdings, P&L, portfolio value
:feature:watchlist      Stock watchlist + price alerts
:feature:performance    30-day charts, portfolio performance
:feature:settings       User preferences, biometric toggle
```

**Dependency rule**: `:feature:*` → `:core:domain` → `:core:data`. Features never depend on each other.

---

## Core Patterns

| Pattern | Key Components | Why |
|---------|---------------|-----|
| **MVVM + UDF** | ViewModel exposes single `StateFlow<UiState>`, Compose collects | Predictable state, lifecycle-aware, survives config changes |
| **MVI (alternative)** | Intent → Reducer → immutable State → Render | Single source of truth — ideal for complex payment flows |
| **Clean Architecture** | Domain (pure Kotlin) → Data (Room + Retrofit) → UI (Compose) | Testable, framework-independent business logic |
| **Hilt DI** | `@HiltViewModel`, `@Inject`, `@Module` — compile-time verification | Zero runtime reflection, testable with `@TestInstallIn` |
| **Coroutines + Flow** | `viewModelScope.launch`, `StateFlow` (hot), `Flow` (cold) | Structured concurrency — cancellation prevents leaked calls |
| **Room + Repository** | Offline-first: emit cached → refresh from network → emit updated | Single source of truth, works without network |
| **Gradle Modularization** | `:core:*` + `:feature:*` — strict module boundaries | Parallel builds, enforced ownership, team scaling |
| **Compose Navigation** | `@Serializable` sealed routes, type-safe `NavHost` | Compile-time route safety, no string-based navigation |

---

## Pattern Comparison (Google Recommendation)

| Aspect | MVC | MVP | MVVM | MVI |
|--------|-----|-----|------|-----|
| UI coupling | High | Low (interface) | None (observable) | None (reactive) |
| State management | Manual | Manual | Lifecycle-retained | Immutable loop |
| Testability | Difficult | Good | Excellent | Excellent |
| Best for | Legacy only | Medium legacy | **Standard modern** | Complex dynamic UIs |
| **Google recommended** | No | No | **Yes (primary)** | Yes (advanced) |

---

## Design Rules

| Rule | Detail |
|------|--------|
| Money | `BigDecimal` only — never `Double`/`Float`. Store as `String` in Room. |
| State | Single `StateFlow<UiState>` per ViewModel — sealed interface (Loading/Content/Error) |
| Concurrency | `viewModelScope.launch` + `flowOn(Dispatchers.IO)` — structured cancellation |
| DI | Hilt `@Inject` — no manual construction, no service locators |
| Navigation | Compose Navigation with `@Serializable` routes — type-safe |
| Biometric | `BiometricPrompt` (`BIOMETRIC_STRONG`) gate before portfolio data |
| Secure storage | `EncryptedSharedPreferences` — never plain `SharedPreferences` for financial data |
| Network | OkHttp + `CertificatePinner` on all API calls |
| Offline | Room as source of truth — emit cached, then refresh |
| Build output | AAB (Android App Bundle) — required by Google Play |

---

## Security

| Layer | Implementation | Standard |
|-------|---------------|----------|
| **Biometric** | BiometricPrompt (AndroidX, `BIOMETRIC_STRONG`) | Gate before financial data |
| **Storage** | EncryptedSharedPreferences (AES256-GCM) | PCI-DSS secure storage |
| **Network** | OkHttp CertificatePinner (SHA-256) | OWASP M3 |
| **Tampering** | Play Integrity API / SafetyNet | Root/tamper detection |
| **Data** | Room with `String` for BigDecimal columns | Precision preservation |

---

## Test Strategy

| Layer | % | Tools |
|-------|---|-------|
| Unit | 50% | JUnit 5, MockK, Turbine (Flow testing) |
| Snapshot | 20% | Paparazzi (Compose screenshot tests) |
| Integration | 20% | Hilt test, Room in-memory DB |
| UI | 10% | Espresso, Compose UI Test |
| **Gate** | **80%** | JaCoCo in CI |

---

## CI/CD

```
ktlint + detekt → assembleDebug → test (JaCoCo ≥80%) → verifyPaparazzi → connectedAndroidTest → bundleRelease → Play Console
```

---

## Backend Connectivity

| Environment | Base URL | Backend |
|-------------|----------|---------|
| Dev (Mac Mini) | `http://192.168.68.20:8000` | Kong → Spring Boot → PostgreSQL / Redis / Kafka |
| Prod (AWS) | `https://api.{domain}.com` | Kong (ECS/EKS) → RDS / ElastiCache / MSK |

API contract: OpenAPI 3.1 (shared with iOS + Web). Generated Kotlin client via `openapi-generator`.

---

## Cross-Reference

| Concern | Source |
|---------|--------|
| Technology versions | `dotfiles/ENTERPRISE-GOLDEN-PATH.md` v4.0.0 |
| Backend services | `Calvin_Infrastructure_Target/README.md` Device 2 |
| AI agent governance | `claude_context_engineering` — Pattern 0, PE Template v3.0 |
| Architecture patterns | `fintech_enterprise_architecture/README.md` Section 1B |
| iOS counterpart | `mobile_engineering/ios/ARCHITECTURE.md` |

---

**Next**: Create `:app` + `:core:domain` + `:core:data` Gradle modules, implement `GetHoldingsUseCase` + `PortfolioViewModel` with TDD.
