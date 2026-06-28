# JJ — System Architecture (Scalability Blueprint)

> **Status:** Draft. Companion to `SPEC.md`, `DATA-MODEL.md`, `ERD.md`.
> This describes how JJ grows from one photography kiosk into a **platform**
> of cooperating apps (invoicing, accounting, orders, delivery, printing)
> without rewrites.

---

## 1. The vision

JJ is not one app — it's a **suite of modules** that share data and talk to
each other:

```
        ┌──────────── JJ Platform ────────────┐
        │                                      │
  Queue/Kiosk   Orders   Invoicing  Accounting │
        │         │          │          │      │
     Printing   Delivery   Reporting   ...      │   ← more added over time
        └──────────────────────────────────────┘
                       shared core
```

Each module can be **developed, updated, and (eventually) deployed
independently** — but they agree on a common language for customers, orders,
and money.

---

## 2. Principles that make it scalable

| Principle | What it buys us |
|---|---|
| **Modular boundaries** | Each app is a *bounded context* with its own logic; others don't reach into its internals. |
| **Shared core (kernel)** | One definition of Customer, Order, Money — reused, never re-invented per app. |
| **Event-driven integration** | Modules react to **events** (e.g. `OrderSettled`) instead of calling each other. Add a new app by subscribing — no edits to existing apps. |
| **Stable UUIDs everywhere** | Cross-module references never collide; safe across devices and future sync. |
| **Append-only event log** | One mechanism serves three needs: decoupling, audit trail, **and** offline→online sync. |
| **Offline-first, sync-ready** | Runs fully local now; the event log replays/merges when online later. |
| **Contracts over coupling** | Modules depend on published event/data *contracts*, not each other's code. |

---

## 3. Recommended shape: modular monolith now → services later

**Do NOT build microservices today.** One location, offline — that would be
cost with no benefit. Instead:

- **Phase A (now):** a **modular monolith**. One app, one local database, but
  the code is split into clear modules with hard internal boundaries and an
  in-process **event bus**. Cheap, simple, fast.
- **Phase B (growth):** when a module needs to scale or run elsewhere
  (e.g. a cloud Accounting service), **extract it**. Because modules already
  talk via events and contracts, extraction is a move — not a rewrite.

> The boundaries you draw on day one are what make Phase B painless. That's the
> whole game.

---

## 4. Module map

| Module | Responsibility | Reacts to | Emits |
|---|---|---|---|
| **Queue / Kiosk** | Check-in, pick package, record payment, issue number | — | `OrderCreated`, `PaymentRecorded`, `TicketIssued` |
| **Orders** (core) | The Order lifecycle; source of truth for who/what | `PaymentRecorded` | `OrderSettled`, `OrderProductionChanged` |
| **Invoicing** | Generate invoices/receipts from orders & contributions | `OrderCreated`, `OrderSettled` | `InvoiceIssued` |
| **Accounting** | Ledgers, daily sales, sponsorship/discount totals | `PaymentRecorded`, `InvoiceIssued` | `LedgerPosted` |
| **Printing** | Print jobs once a shoot is done | `OrderProductionChanged → shot` | `PrintQueued`, `PrintDone` |
| **Delivery / Release** | Track storage → handover to customer/school | `PrintDone`, `OrderSettled` | `ReleasedToCustomer` |
| **Reporting** | Cross-module dashboards | all of the above | — |

> **The lifecycle is the wiring.** `to_shoot → shot → in_storage → released`
> are the exact moments one module hands off to the next. We already designed
> the backbone; this just names the hand-offs.

---

## 5. The shared core (kernel)

The few concepts every module agrees on. Defined once, imported everywhere:

- **Customer / Student identity** (last/first/MI, course, section, batchYear, contact)
- **Order** (the per-person spine) + **SchoolBatch**
- **Money**: `Contribution` (tagged by source), discounts, the settle rule
- **IDs, timestamps, soft-delete conventions**

Everything in `DATA-MODEL.md` *is* the kernel. Modules add their own private
data (e.g. Printing's job queue) but never redefine a Customer.

---

## 6. How modules talk: events

Instead of `Accounting` importing `Kiosk`'s code, the Kiosk **publishes** an
event and anyone interested **subscribes**:

```
Kiosk           →  emits  →  PaymentRecorded { orderId, source, amount, at }
                                   │
            ┌──────────────────────┼───────────────────────┐
            ▼                      ▼                        ▼
        Orders                Accounting                Invoicing
   (recompute settled)     (post to ledger)        (maybe issue receipt)
```

Adding a future app (say, **SMS notifications**) means: subscribe to
`ReleasedToCustomer`. **Zero changes** to existing modules. That's scalability.

### Event shape (contract)
```
{
  id:        uuid,
  type:      "PaymentRecorded",
  occurredAt: timestamp,
  actor:     "staff:jane",
  payload:   { ... module-agnostic data ... },
  version:   1            // contracts are versioned so they can evolve
}
```

---

## 7. The event log = sync engine (for free)

Every event is appended to a local **event log**. This single structure powers:

1. **Decoupling** — modules read the log instead of each other.
2. **Audit** — a complete, ordered history of everything that happened.
3. **Sync (later)** — when online, push local events up and pull remote ones;
   UUIDs + `occurredAt` + last-write-wins (or per-aggregate ordering) merge
   cleanly. No "big sync rewrite" — the log was sync-ready from day one.

This is why we chose append-only contributions and computed (not stored)
status back in `DATA-MODEL.md` — replaying events must always rebuild the same
state.

---

## 8. Suggested tech direction (to confirm — see open question)

A pragmatic, scalable, offline-first stack:

- **Local backend** (single process) exposing a clean API + event bus.
- **Local database**: SQLite now (file-based, zero-config, offline) →
  swappable to Postgres when cloud sync arrives. Same schema shape.
- **Frontends as separate apps over one backend**: a **Kiosk** UI (locked
  down, touch) and an **Admin** UI (full control), more later — all talking to
  the same core. This is the "different apps that talk to each other" you want,
  starting on day one.
- **Language/stack**: TBD with you. A TypeScript stack (one language across
  backend + web frontends) keeps the team small and the shared kernel literally
  shared as code. Alternatives open.

> Nothing above forces a choice yet — but it shows the path is real and cheap.

---

## 9. Phasing roadmap

1. **v1 — Photography core inside the modular monolith**
   Kiosk + Admin, Orders, payments recorded, queue, release. Event log running
   internally even though only one app uses it yet.
2. **v2 — Invoicing & Accounting modules** subscribe to existing events.
3. **v3 — Printing & Delivery** modules formalize the production hand-offs.
4. **v4 — Online sync & multi-location**, replaying the event log to the cloud.
5. **vN — Extract** any module that needs to scale independently.

Each phase **adds**; none requires rewriting what came before. That is the
definition of "scalable" we're designing for.

---

## 10. Open questions

- [ ] **Tech stack** confirmation (language, web vs desktop kiosk shell).
- [ ] Is **Admin** a separate app from the **Kiosk** from day one (recommended), or one app with role-gating first?
- [ ] First module *after* photography — Invoicing or Accounting? (drives v2.)
- [ ] Single shared local DB vs. per-module schemas inside it.
