---
name: "nao-golang-ddd"
description: "DDD guide for Golang backend. Progressive 3‑level framework, dependency inversion, Go idioms, and red lines."
---

# Golang DDD

## 1. When to Apply DDD (Decision Tree)

1. **Is it pure CRUD?** → Use Transaction Script (no DDD).
2. **Has complex rules?** (state machines, pricing, inventory) → proceed.
3. **Single team & single deployable?** → Level 1 (lightweight) or Level 2 (modular).
4. **Multiple teams / multiple services?** → Level 3 (microservices).
5. **Legacy system?** Extract the core aggregate first; move validation into entity methods.

## 2. Go Project Layout (Standard)

| Directory               | Responsibility                                                                                           | Visibility      |
|-------------------------|----------------------------------------------------------------------------------------------------------|-----------------|
| `cmd/`                  | Entry points (`main.go`): `api`, `worker`, `migrate`.                                                    | Executable      |
| `internal/`             | Private code – all business logic, adapters.                                                             | Internal        |
| `internal/domain/`      | Aggregates, Entities, VOs, **Repository interfaces**, domain errors. **Zero external dependencies**.     | Internal        |
| `internal/domain/shared/` | Shared VOs (Money, Address) and common errors.                                                        | Internal        |
| `internal/application/` | UseCase handlers (Services), DTOs (Commands/Queries), **outbound ports** (e.g., EventPublisher).         | Internal        |
| `internal/infrastructure/` | Repository impls, MQ clients, RPC clients, mappers (DB ↔ Domain).                                     | Internal        |
| `internal/interfaces/`  | HTTP/gRPC handlers, middleware, consumers. Param binding, auth, DTO conversion – **no business logic**. | Internal        |
| `pkg/`                  | Public contracts (Protobuf/OpenAPI structs). **No business logic**.                                      | External        |

## 3. Progressive Levels

| Aspect                | Level 1 (Lightweight Monolith)                                  | Level 2 (Modular Monolith)                                                                 | Level 3 (Microservices)                                                                         |
|-----------------------|----------------------------------------------------------------|--------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| **Domain depth**      | Anemic/rich entities, simple interfaces.                       | Aggregates, Repository interfaces, domain events defined.                                   | Same as L2 + strict Bounded Contexts.                                                           |
| **Transaction mgmt**  | `db.Begin()` in Application service.                           | **Context‑propagated `*sql.Tx`** with closure‑based commit/rollback.                      | Same as L2, plus **Saga** or **Outbox** patterns.                                               |
| **Domain Events**     | Optional.                                                      | In‑memory bus: events collected inside transaction, dispatched after commit.               | Message queue with Outbox table for at‑least‑once delivery.                                    |
| **Modularity**        | All code under one `internal` package.                         | Sub‑directories per domain (e.g., `order/`, `user/`); shared kernel allowed.               | Multiple `cmd/` processes (API, worker); cross‑service via `pkg/contracts`.                    |
| **Concurrency**       | Database row locks.                                            | **Optimistic lock (version field)** on aggregates.                                         | Same as L2 + distributed locks (Redis) when needed.                                            |

## 4. Dependency Inversion (The Golden Rule)

**Flow:** `Interface → Application → Domain ← Infrastructure`

- **Domain** defines repository interfaces (abstractions).
- **Infrastructure** implements them.
- **Application** depends only on Domain interfaces – never on concrete infra.
- Assembly in `main.go` or Wire (explicit constructor injection). **No Service Locator, no reflection.**

## 5. Upgrade Triggers

- **L1 → L2** when:
  - An aggregate has >3 child entities.
  - Cross‑entity invariants need aggregate root consistency.
  - Team >3, requiring clear module boundaries.

- **L2 → L3** when:
  - Databases must be split per domain.
  - Cross‑domain operations need eventual consistency (e.g., async notifications).
  - A single module requires independent horizontal scaling.

## 6. Code Review Red Lines (Mandatory)

- [ ] `internal/domain/` imports **no** ORM (GORM), web (Gin), or RPC framework.
- [ ] Application layer contains **no business rules** like `if order.Status == Paid` – move to domain method.
- [ ] HTTP handlers do **not** call Repository directly – must go through Application Service.
- [ ] Cross‑service sharing uses `pkg/contracts` or separate Protobuf repo – **never** share `internal/domain`.
- [ ] Aggregate updates check version field (optimistic locking) for concurrency.

## 7. Go‑Specific Idioms & Conventions

- **DI:** Manual construction in `cmd/api/main.go` – Config → DB → Repo → Service → Handler. No framework annotations.
- **Errors:** Domain defines sentinel errors (`var ErrOrderCanceled = errors.New("...")`). Application layer maps them to HTTP statuses (e.g., 409). **Never `panic` in business logic.**
- **Value Objects:** Provide factory functions (e.g., `NewMoney(amount, currency)`) – avoid bare structs to prevent zero‑value pollution.
- **Context:** All I/O methods (DB, RPC) take `context.Context` as **first parameter** for tracing, timeouts, and transaction propagation.

## 8. Common Misconceptions

- **DDD = Microservices?** No – DDD is a modelling approach; it works perfectly in monoliths.
- **Every module needs DDD?** Only the **Core Domain** – support features can use simple scripts.
- **Must use Event Sourcing / CQRS?** Only if audit trails or drastically different read/write models are required. Default to relational DB + lightweight domain events.
- **Repository must always return aggregates?** For queries that don’t change state, return read‑only DTOs directly to avoid unnecessary hydration.

## 9. Testing Strategy

| Layer           | Tools                     | Focus                                                      |
|-----------------|---------------------------|------------------------------------------------------------|
| Domain          | `testing` + `go-cmp`      | Entity invariants, VO methods, error scenarios.           |
| Application     | `testing` + mocks         | UseCase orchestration, transaction boundaries, port calls. |
| Infrastructure  | `testing` + `testcontainers` | Repository mapping, SQL correctness, MQ/RPC integration. |
| Interfaces      | `httptest` / `grpctest`   | Handler request/response, status codes, middleware.       |

## 10. Migration Paths (Legacy to DDD)

1. **Identify core aggregate** and extract it into `internal/domain/`.
2. Move validation logic from Service layer into entity methods.
3. Define Repository interface in Domain; keep existing DB access as initial implementation.
4. Replace direct DB calls in Services with Repository calls.
5. Gradually extract sub‑domains into separate packages (L2) or services (L3).

## 11. Quick FAQ

- **Transaction in Application?** Yes – use a closure that receives `*sql.Tx`; rollback on error, commit on success.
- **How to handle concurrency?** Use version field in aggregates; increment and check in UPDATE `WHERE version = old`.
- **How to pass user identity?** Put user context (e.g., `userID`) into `context.Context` at the middleware level, retrieve in Application.
- **What about caching?** Cache is infrastructure – defined as a separate port in Application, implemented in Infrastructure. Cache invalidation is a domain concern, but the cache store is not.