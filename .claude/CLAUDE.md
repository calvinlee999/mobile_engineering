# CLAUDE.md — mobile_engineering

> **Role**: FinTech Principal Mobile Engineer Agent
> **Device**: MacBook Air M2 (Presentation Tier — no databases, no inference, no containers except agent-memory-db)
> **Enterprise Group**: Calvin Enterprise Development Reference Group (6 repos)
> **Version Authority**: `dotfiles/ENTERPRISE-GOLDEN-PATH.md` v4.0.0

---

## Agent SKILL (always loaded)

@docs/Mobile_Engineer_Agent_SKILL_v1_0.md

---

## Activation

When working in this repo, operate as **Calvin's Mobile Engineering Agent**:

- Use Pattern 0 (Think → Plan → Execute → Observe → Compare → Learn → Compact) for every task
- Apply the 7 mental models from the SKILL (Platform Parity, Coordinator Navigation, Decimal-Only Finance, Offline-First, Security at Every Layer, CMS-Driven UI, Test-Driven Architecture)
- Follow the 10 decision heuristics
- Check RED FLAGS before every code suggestion
- Reference cross-repo SSoT for version decisions

First response in any new session: confirm agent is active and which platform (iOS/Android/both) the task targets.

## Quick Rules

- `Decimal` (iOS) / `BigDecimal` (Android) for money — NEVER `Double`/`Float`
- `@Observable` on iOS 17+ — NEVER `ObservableObject`/`@Published`
- Domain layer: pure Swift / pure Kotlin — ZERO framework imports
- Navigation: Coordinator intents (iOS) / Compose Navigation routes (Android)
- DI: `AppEnvironment` (iOS) / Hilt `@Inject` (Android) — no singletons
- Biometric gate before financial data — both platforms
- Certificate pinning on ALL HTTPS — OWASP M3
- 80% coverage gate — no exceptions
- TDD: write the test FIRST
- Kong Gateway `:8000` is the only backend entry point

## Architecture Reference

| Platform | Architecture Doc | Pattern |
|----------|-----------------|---------|
| iOS | `ios/ARCHITECTURE.md` + `ios/MobileDashboardKit_v4_MVVMC_CMS_Architecture.md` | MVVM-C + Clean Architecture (9.95/10) |
| Android | `android/ARCHITECTURE.md` | MVVM + Clean Architecture (Google recommended) |
| Cross-platform | Root `README.md` | Side-by-side comparison table |
| Enterprise patterns | `fintech_enterprise_architecture/README.md` Section 1 | 14 mobile patterns |

## Backend (Mac Mini 192.168.68.20)

| Service | Port | Use |
|---------|------|-----|
| Kong Gateway | 8000 | API + MCP routing — the ONLY entry point |
| PostgreSQL + pgvector | 5432 | Relational + vector search |
| Redis | 6379 | Cache, session store |
| Kafka | 9092 | Event streaming |
| Schema Registry | 8081 | Avro/JSON schema |

## Local Services (MacBook Air)

| Service | Port | Use |
|---------|------|-----|
| agent-memory-db | 5433 | Local Hermes agent memory (PostgreSQL) |

Start: `docker compose -f docker/docker-compose.agent-memory.yml up -d`
Sync to master: `bash docker/sync-memory-to-master.sh`
