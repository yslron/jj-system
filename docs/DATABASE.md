# JJ — Database Architecture (Photography Module)

> **Status:** Draft schema. Scope: **photography only**, shared by the
> **Kiosk** and **Admin** apps over one core database.
> Dialect shown is **SQLite** (offline-first default); it maps cleanly to
> Postgres later (see §8). Companion to `DATA-MODEL.md` / `ERD.md`.

---

## 0. Cross-cutting decisions

| Decision | Why |
|---|---|
| **Money = INTEGER centavos** | ₱500.00 → `50000`. Never use floats for money — they round wrong. |
| **IDs = TEXT UUIDs** | Globally unique; safe across devices for future sync. |
| **Soft delete** (`deleted_at`) | Never hard-delete; sync needs tombstones. Queries filter `deleted_at IS NULL`. |
| **Timestamps** = ISO-8601 TEXT (UTC) | `created_at`, `updated_at` on every table. |
| **Enums = CHECK constraints** | DB rejects bad values; no separate lookup tables needed yet. |
| **Derived values = VIEWS** | `net_due`, `paid`, `payment_status` are computed, never stored. |
| **Customer = flat columns** | Sort/search rosters by `last_name` efficiently. |

---

## 1. Shared core vs. app access

Both apps talk to the **same database** (the shared core). The difference is
**what each is allowed to write** — enforced in the app layer and documented
here as the contract:

| Table | Kiosk (self-service) | Admin (PIN) |
|---|---|---|
| `packages`, `discounts`, `settings`, `users` | **read** | **read + write** |
| `schools`, `school_batches` | read | read + write |
| `orders` | **insert** (self-pay walk-ins) | full |
| `contributions` | insert `cash`/`gcash` only | full (incl. `sponsorship`, `school`) |
| `queue_tickets` | insert + advance status | full |
| discount / sponsorship / release actions | **never** | yes |
| `event_log` | append | append |

> Kiosk can take a walk-in and a cash payment; everything sensitive
> (discounts, sponsorship, releasing photos, settings) is Admin-only.

---

## 2. Settings tables (configured, not hardcoded)

```sql
CREATE TABLE packages (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    service_type TEXT NOT NULL CHECK (service_type IN
                     ('family','solo','portraits','school')),
    list_price   INTEGER NOT NULL,            -- centavos
    active       INTEGER NOT NULL DEFAULT 1,  -- 0/1 bool
    notes        TEXT,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL,
    deleted_at   TEXT
);

CREATE TABLE discounts (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,               -- "Senior Citizen", "PWD"
    kind         TEXT NOT NULL CHECK (kind IN ('percentage','fixed')),
    value        INTEGER NOT NULL,            -- percent (20) OR centavos
    requires_id  INTEGER NOT NULL DEFAULT 0,  -- force ID number/name capture
    active       INTEGER NOT NULL DEFAULT 1,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL,
    deleted_at   TEXT
);

CREATE TABLE settings (             -- misc app config (business name, queue prefix…)
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,       -- JSON or scalar
    updated_at TEXT NOT NULL
);

CREATE TABLE users (                -- staff identities + PIN for Admin
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    role       TEXT NOT NULL CHECK (role IN ('staff','admin')),
    pin_hash   TEXT NOT NULL,       -- hashed, never plaintext
    active     INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
```

---

## 3. School tables

```sql
CREATE TABLE schools (
    id             TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    contact_person TEXT,
    contact_info   TEXT,
    notes          TEXT,
    created_at     TEXT NOT NULL,
    updated_at     TEXT NOT NULL,
    deleted_at     TEXT
);

CREATE TABLE school_batches (
    id                    TEXT PRIMARY KEY,
    school_id             TEXT NOT NULL REFERENCES schools(id),
    label                 TEXT NOT NULL,
    event_date            TEXT,                 -- ISO date
    arrangement           TEXT NOT NULL CHECK (arrangement IN
                              ('school_pays','students_pay')),
    agreed_amount         INTEGER,              -- centavos; for school_pays
    production_status     TEXT NOT NULL DEFAULT 'to_photoshoot' CHECK
                              (production_status IN ('to_photoshoot','in_progress',
                               'shot','in_storage','released')),
    release_mode          TEXT NOT NULL DEFAULT 'batch' CHECK
                              (release_mode IN ('batch','per_student')),
    release_override      INTEGER NOT NULL DEFAULT 0,
    release_override_note TEXT,
    created_at            TEXT NOT NULL,
    updated_at            TEXT NOT NULL,
    deleted_at            TEXT
);
-- payment_status is DERIVED (see §6), not a column.
```

---

## 4. Orders (the per-person spine)

```sql
CREATE TABLE orders (
    id                 TEXT PRIMARY KEY,
    package_id         TEXT NOT NULL REFERENCES packages(id),
    school_batch_id    TEXT REFERENCES school_batches(id),  -- null = walk-in
    coverage_type      TEXT NOT NULL CHECK (coverage_type IN
                           ('self_pay','school_covered','sponsored')),

    -- customer identity (flattened for sort/search)
    cust_last_name     TEXT NOT NULL,
    cust_first_name    TEXT NOT NULL,
    cust_middle_initial TEXT,
    cust_course        TEXT,        -- school only
    cust_section       TEXT,        -- school only
    cust_batch_year    TEXT,        -- school only
    cust_contact       TEXT,        -- phone/email, optional

    -- price snapshot
    list_price         INTEGER NOT NULL,            -- centavos, copied at sale

    -- discount snapshot (null = none); one per order, no stacking
    discount_id        TEXT REFERENCES discounts(id),
    discount_name      TEXT,
    discount_kind      TEXT CHECK (discount_kind IN ('percentage','fixed')),
    discount_value     INTEGER,
    discount_amount    INTEGER,     -- centavos actually taken off
    discount_id_number TEXT,        -- required when discount.requires_id
    discount_id_name   TEXT,
    discount_applied_by TEXT,       -- staff who verified

    -- production lifecycle
    production_status  TEXT NOT NULL DEFAULT 'to_shoot' CHECK
                           (production_status IN ('to_shoot','shot',
                            'in_storage','released')),
    released_at        TEXT,
    released_by        TEXT,

    notes              TEXT,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL,
    deleted_at         TEXT
);

CREATE INDEX idx_orders_batch    ON orders(school_batch_id);
CREATE INDEX idx_orders_lastname ON orders(cust_last_name, cust_first_name);
CREATE INDEX idx_orders_prod     ON orders(production_status);
-- net_due is DERIVED: list_price - COALESCE(discount_amount,0)
```

---

## 5. Contributions, queue, event log

```sql
CREATE TABLE contributions (
    id              TEXT PRIMARY KEY,
    order_id        TEXT REFERENCES orders(id),
    school_batch_id TEXT REFERENCES school_batches(id),
    source          TEXT NOT NULL CHECK (source IN
                        ('cash','gcash','school','sponsorship')),
    amount          INTEGER NOT NULL,           -- centavos
    recorded_by     TEXT NOT NULL,
    note            TEXT,
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    deleted_at      TEXT,
    -- XOR: belongs to exactly one of order OR batch, never both/neither
    CHECK ((order_id IS NOT NULL) <> (school_batch_id IS NOT NULL))
);
CREATE INDEX idx_contrib_order  ON contributions(order_id);
CREATE INDEX idx_contrib_batch  ON contributions(school_batch_id);
CREATE INDEX idx_contrib_source ON contributions(source);

CREATE TABLE queue_tickets (
    id         TEXT PRIMARY KEY,
    order_id   TEXT NOT NULL REFERENCES orders(id),
    business_date TEXT NOT NULL,                 -- for per-day numbering
    number     TEXT NOT NULL,                    -- "A-014"
    purpose    TEXT NOT NULL DEFAULT 'shoot' CHECK (purpose IN ('shoot','pickup')),
    lane       TEXT,                             -- future: per-booth/studio-vs-school
    status     TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN
                   ('waiting','called','serving','done','skipped')),
    called_at  TEXT,
    served_by  TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE INDEX idx_tickets_status ON queue_tickets(business_date, status);

-- per-day sequential counter (atomic number issuance)
CREATE TABLE queue_counters (
    business_date TEXT NOT NULL,
    lane          TEXT NOT NULL DEFAULT 'main',
    last_number   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (business_date, lane)
);

-- append-only event log: decoupling + audit + future sync (ARCHITECTURE.md §7)
CREATE TABLE event_log (
    id             TEXT PRIMARY KEY,
    seq            INTEGER,                       -- local monotonic order
    type           TEXT NOT NULL,                 -- "PaymentRecorded", …
    aggregate_type TEXT NOT NULL,                 -- "order","school_batch",…
    aggregate_id   TEXT NOT NULL,
    occurred_at    TEXT NOT NULL,
    actor          TEXT,                          -- "staff:jane"
    payload        TEXT NOT NULL,                 -- JSON
    version        INTEGER NOT NULL DEFAULT 1,
    synced         INTEGER NOT NULL DEFAULT 0     -- 0 until pushed to cloud later
);
CREATE INDEX idx_events_aggregate ON event_log(aggregate_type, aggregate_id);
CREATE INDEX idx_events_unsynced  ON event_log(synced, seq);
-- INSERT-only by convention: never UPDATE/DELETE rows here.
```

---

## 6. Derived views (single source of truth for money/status)

```sql
-- how much has been paid toward each order
CREATE VIEW order_paid AS
SELECT o.id AS order_id,
       COALESCE(SUM(c.amount), 0) AS paid
FROM orders o
LEFT JOIN contributions c
       ON c.order_id = o.id AND c.deleted_at IS NULL
WHERE o.deleted_at IS NULL
GROUP BY o.id;

-- net due + payment status for individual (self_pay/sponsored) orders
CREATE VIEW order_status AS
SELECT o.id AS order_id,
       (o.list_price - COALESCE(o.discount_amount,0)) AS net_due,
       p.paid,
       CASE
         WHEN p.paid <= 0                                          THEN 'unpaid'
         WHEN p.paid <  (o.list_price - COALESCE(o.discount_amount,0)) THEN 'partial'
         ELSE 'paid'
       END AS payment_status
FROM orders o
JOIN order_paid p ON p.order_id = o.id
WHERE o.deleted_at IS NULL;
-- NOTE: school_covered orders inherit payment_status from their batch
--       (joined in the app/report layer; see DATA-MODEL §6).

-- batch payment status (school_pays)
CREATE VIEW batch_status AS
SELECT b.id AS batch_id,
       b.agreed_amount,
       COALESCE(SUM(c.amount),0) AS paid,
       CASE
         WHEN COALESCE(SUM(c.amount),0) <= 0                 THEN 'unpaid'
         WHEN COALESCE(SUM(c.amount),0) <  b.agreed_amount   THEN 'partial'
         ELSE 'paid'
       END AS payment_status
FROM school_batches b
LEFT JOIN contributions c
       ON c.school_batch_id = b.id AND c.deleted_at IS NULL
WHERE b.deleted_at IS NULL
GROUP BY b.id;
```

**Release eligibility** (computed in app, per `DATA-MODEL.md` §6):
- individual order → `payment_status = 'paid'` (strict)
- school-covered order → `batch.payment_status = 'paid' OR batch.release_override = 1`

---

## 7. Reporting queries (fall out of the schema)

```sql
-- Real cash collected today
SELECT SUM(amount) FROM contributions
WHERE source IN ('cash','gcash') AND deleted_at IS NULL
  AND date(created_at) = date('now');

-- Sponsorship value given
SELECT SUM(amount) FROM contributions WHERE source = 'sponsorship';

-- Discounts given
SELECT SUM(discount_amount) FROM orders WHERE discount_amount IS NOT NULL;

-- Outstanding balances (partial individual orders)
SELECT order_id, net_due - paid AS balance
FROM order_status WHERE payment_status = 'partial';
```

---

## 8. SQLite → Postgres mapping (when cloud sync arrives)

| SQLite | Postgres |
|---|---|
| `TEXT` UUID | `uuid` |
| `INTEGER` bool (0/1) | `boolean` |
| `INTEGER` centavos | `bigint` (or `numeric` if preferred) |
| `TEXT` timestamp | `timestamptz` |
| `CHECK (x IN …)` | same, or native `enum` types |
| `payload TEXT` (JSON) | `jsonb` |

Schema shape is identical; only column types change. The `event_log.synced`
flag is the hook the future sync worker drains.

---

## 9. Open questions

- [ ] Queue numbering format + whether **lanes** exist in v1 (studio vs school / per booth).
- [ ] Do school-covered orders need their own `order_status` view variant, or handle in app?
- [ ] Roster pre-load: bulk-insert orders before shoot day vs. one-by-one entry.
- [ ] Auth: is a PIN enough for Admin, or named user logins from day one?
