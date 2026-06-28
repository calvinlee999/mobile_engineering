# Android FinTech Architecture — MVVM + Clean Architecture

> **Platform**: API 26+ · Kotlin · Jetpack Compose · MVVM + Clean Architecture
> **Standard**: Google official architecture recommendation
> **Versions**: Governed by `dotfiles/ENTERPRISE-GOLDEN-PATH.md` v4.0.0
> **Cross-platform**: See `fintech_enterprise_architecture/README.md` Section 1 for iOS/Android comparison
> **Status**: Ready to implement

---

## Architecture Overview

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

## Module Structure (Gradle Kotlin DSL)

```
:app                              ← Application entry, Hilt setup, Navigation host
:core:data                        ← Repository implementations, Room DB, Retrofit
:core:domain                      ← UseCases, domain models, repository interfaces
:core:ui                          ← Design system, shared Compose components, theme
:core:network                     ← OkHttp client, certificate pinning, interceptors
:core:security                    ← BiometricPrompt, EncryptedSharedPreferences
:feature:portfolio                ← Investing dashboard (holdings, P&L)
:feature:watchlist                ← Stock watchlist + price alerts
:feature:performance              ← 30-day charts, portfolio performance
:feature:settings                 ← User preferences, biometric toggle
```

**Dependency rule**: `:feature:*` → `:core:domain` → `:core:data`. Features never depend on each other.

---

## Core Patterns

### 1. MVVM + Unidirectional Data Flow

```kotlin
@HiltViewModel
class PortfolioViewModel @Inject constructor(
    private val getHoldingsUseCase: GetHoldingsUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow<PortfolioUiState>(PortfolioUiState.Loading)
    val uiState: StateFlow<PortfolioUiState> = _uiState.asStateFlow()

    init { loadHoldings() }

    fun onEvent(event: PortfolioEvent) {
        when (event) {
            is PortfolioEvent.Refresh -> loadHoldings()
            is PortfolioEvent.SelectHolding -> _uiState.update { /* navigate */ }
        }
    }

    private fun loadHoldings() {
        viewModelScope.launch {
            getHoldingsUseCase().collect { result ->
                _uiState.value = when (result) {
                    is Result.Success -> PortfolioUiState.Content(result.data)
                    is Result.Error -> PortfolioUiState.Error(result.message)
                }
            }
        }
    }
}

sealed interface PortfolioUiState {
    data object Loading : PortfolioUiState
    data class Content(val holdings: List<Holding>) : PortfolioUiState
    data class Error(val message: String) : PortfolioUiState
}

sealed interface PortfolioEvent {
    data object Refresh : PortfolioEvent
    data class SelectHolding(val ticker: String) : PortfolioEvent
}
```

### 2. Domain Layer — Pure Kotlin

```kotlin
class GetHoldingsUseCase @Inject constructor(
    private val repository: HoldingRepository
) {
    operator fun invoke(): Flow<Result<List<Holding>>> = repository.getHoldings()
}

data class Holding(
    val ticker: String,
    val companyName: String,
    val quantity: Int,
    val averageCost: BigDecimal,    // NEVER Double/Float
    val currentPrice: BigDecimal,   // NEVER Double/Float
) {
    val totalValue: BigDecimal get() = currentPrice * quantity.toBigDecimal()
    val unrealizedPnL: BigDecimal get() = (currentPrice - averageCost) * quantity.toBigDecimal()
}
```

### 3. Data Layer — Repository + Room + Retrofit

```kotlin
class HoldingRepositoryImpl @Inject constructor(
    private val holdingDao: HoldingDao,
    private val apiService: FinTechApiService
) : HoldingRepository {

    override fun getHoldings(): Flow<Result<List<Holding>>> = flow {
        // Offline-first: emit cached data immediately
        val cached = holdingDao.getAllHoldings().map { it.toDomain() }
        if (cached.isNotEmpty()) emit(Result.Success(cached))

        // Then refresh from network
        try {
            val remote = apiService.getHoldings()
            holdingDao.upsertAll(remote.map { it.toEntity() })
            emit(Result.Success(holdingDao.getAllHoldings().map { it.toDomain() }))
        } catch (e: Exception) {
            if (cached.isEmpty()) emit(Result.Error(e.message ?: "Network error"))
        }
    }.flowOn(Dispatchers.IO)
}

@Entity(tableName = "holdings")
data class HoldingEntity(
    @PrimaryKey val ticker: String,
    val companyName: String,
    val quantity: Int,
    val averageCost: String,     // BigDecimal stored as String
    val currentPrice: String,
    val lastUpdated: Long
)

@Dao
interface HoldingDao {
    @Query("SELECT * FROM holdings ORDER BY ticker")
    suspend fun getAllHoldings(): List<HoldingEntity>

    @Upsert
    suspend fun upsertAll(holdings: List<HoldingEntity>)
}
```

### 4. Hilt Dependency Injection

```kotlin
@Module
@InstallIn(SingletonComponent::class)
object DataModule {
    @Provides @Singleton
    fun provideDatabase(@ApplicationContext context: Context): FinTechDatabase =
        Room.databaseBuilder(context, FinTechDatabase::class.java, "fintech.db").build()

    @Provides
    fun provideHoldingDao(db: FinTechDatabase): HoldingDao = db.holdingDao()

    @Provides @Singleton
    fun provideRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            .baseUrl("http://192.168.68.20:8000/")  // Kong Gateway (dev)
            .client(okHttpClient)
            .addConverterFactory(MoshiConverterFactory.create())
            .build()
}
```

### 5. Security — FinTech Standard

```kotlin
// Biometric gate
class BiometricAuthManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    fun authenticate(
        activity: FragmentActivity,
        onSuccess: () -> Unit,
        onError: (String) -> Unit
    ) {
        val prompt = BiometricPrompt(activity, executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: AuthenticationResult) = onSuccess()
                override fun onAuthenticationError(code: Int, msg: CharSequence) = onError(msg.toString())
            })
        prompt.authenticate(BiometricPrompt.PromptInfo.Builder()
            .setTitle("Authenticate")
            .setNegativeButtonText("Cancel")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .build())
    }
}

// Secure storage — NEVER SharedPreferences for financial data
val encryptedPrefs = EncryptedSharedPreferences.create(
    context, "secure_prefs",
    MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
    PrefKeyEncryptionScheme.AES256_SIV,
    PrefValueEncryptionScheme.AES256_GCM
)

// Certificate pinning
val okHttpClient = OkHttpClient.Builder()
    .certificatePinner(CertificatePinner.Builder()
        .add("192.168.68.20", "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
        .build())
    .build()
```

### 6. Navigation — Compose Navigation + Type-Safe Routes

```kotlin
@Serializable sealed interface Route {
    @Serializable data object Portfolio : Route
    @Serializable data object Watchlist : Route
    @Serializable data class StockDetail(val ticker: String) : Route
    @Serializable data object Settings : Route
}

@Composable
fun AppNavHost(navController: NavHostController = rememberNavController()) {
    NavHost(navController, startDestination = Route.Portfolio) {
        composable<Route.Portfolio> { PortfolioScreen(onSelectHolding = { navController.navigate(Route.StockDetail(it)) }) }
        composable<Route.Watchlist> { WatchlistScreen() }
        composable<Route.StockDetail> { backStackEntry ->
            val route = backStackEntry.toRoute<Route.StockDetail>()
            StockDetailScreen(ticker = route.ticker)
        }
    }
}
```

---

## Design Rules

| Rule | Detail |
|------|--------|
| Money | `BigDecimal` only — never `Double`/`Float` in domain or UI. Store as `String` in Room. |
| State | Single `StateFlow<UiState>` per ViewModel — sealed interface with Loading/Content/Error |
| Concurrency | `viewModelScope.launch` + `flowOn(Dispatchers.IO)` — structured cancellation |
| DI | Hilt `@Inject` everywhere — no manual construction, no service locators |
| Navigation | Compose Navigation with `@Serializable` routes — type-safe, no string-based |
| Biometric | `BiometricPrompt` gate before portfolio data — `BIOMETRIC_STRONG` only |
| Secure storage | `EncryptedSharedPreferences` — never plain `SharedPreferences` for financial data |
| Network | OkHttp + `CertificatePinner` — certificate pinning on all API calls |
| Offline | Room as single source of truth — emit cached, then refresh from network |
| Build output | AAB (Android App Bundle) — required by Google Play |
| Tests | JUnit 5 + MockK + Turbine (Flow testing) + Paparazzi (screenshot) |
| Coverage | 80% JaCoCo gate in CI |

---

## Test Strategy

| Layer | Coverage | Tools | What to Test |
|-------|----------|-------|-------------|
| Unit (50%) | JUnit 5, MockK | ViewModel state transitions, UseCase logic, Repository mapping |
| Snapshot (20%) | Paparazzi | Compose screen states (loading, content, error, dark mode) |
| Integration (20%) | Hilt test, Room in-memory | Repository + DAO + ViewModel wired together |
| UI (10%) | Espresso, Compose UI Test | Critical user journeys, biometric mock |

```kotlin
// ViewModel test with Turbine (Flow testing)
@Test
fun `loadHoldings emits Content state`() = runTest {
    val useCase = mockk<GetHoldingsUseCase>()
    every { useCase() } returns flowOf(Result.Success(testHoldings))

    val vm = PortfolioViewModel(useCase)

    vm.uiState.test {
        assertThat(awaitItem()).isInstanceOf(PortfolioUiState.Loading::class.java)
        assertThat(awaitItem()).isInstanceOf(PortfolioUiState.Content::class.java)
    }
}
```

---

## CI/CD Pipeline

```
PR opened
  │
  ▼
ktlint + detekt (lint)      ← fails on violations
  │
  ▼
./gradlew assembleDebug     ← compilation check
  │
  ▼
./gradlew test              ← unit + integration tests
  + JaCoCo ≥80%             ← coverage gate
  │
  ▼
./gradlew verifyPaparazzi   ← screenshot regression tests
  │
  ▼
./gradlew connectedAndroidTest  ← Espresso on emulator (CI)
  │
  ▼
./gradlew bundleRelease     ← AAB for Play Console
  + Play Console upload     ← (main branch only)
```

---

## Backend Connectivity

All API calls go through Kong Gateway — same backend as iOS and Web.

| Environment | Base URL | Config |
|-------------|----------|--------|
| **Dev** (Mac Mini) | `http://192.168.68.20:8000` | `local.properties` |
| **Prod** (AWS) | `https://api.{domain}.com` | Build variant |

**API contract**: OpenAPI 3.1 spec (shared with iOS + Web). Generated Kotlin client via `openapi-generator`.

---

## Cross-Reference

| Concern | Source | Reference |
|---------|--------|-----------|
| Technology versions | `dotfiles/ENTERPRISE-GOLDEN-PATH.md` v4.0.0 | Android Studio latest stable, API 34, Node 22 LTS |
| Backend services | `Calvin_Infrastructure_Target/README.md` Device 2 | Kong :8000, PostgreSQL :5432, Redis :6379, Kafka :9092 |
| AI agent governance | `claude_context_engineering` | Pattern 0 operating model, PE Template v3.0 |
| Architecture patterns | `fintech_enterprise_architecture/README.md` Section 1B | 8 Android patterns, cross-platform comparison |
| iOS counterpart | `mobile_engineering/ios/` | MVVM-C + Clean Architecture (9.95/10 panel score) |

---

**Status**: Architecture defined, ready for Xcode/Android Studio implementation.
**Next**: Create `:app` + `:core:domain` + `:core:data` Gradle modules, implement `GetHoldingsUseCase` + `PortfolioViewModel` with TDD.
