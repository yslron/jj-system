-- JJ — Photography Module schema (SQLite)
-- Importable into drawDB, and the basis for creating the real database.
-- Mirrors docs/DATABASE.md. Money is INTEGER centavos. Tables only (views live in DATABASE.md).

CREATE TABLE packages (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    service_type TEXT NOT NULL CHECK (service_type IN ('family','solo','portraits','school')),
    list_price   INTEGER NOT NULL,
    active       INTEGER NOT NULL DEFAULT 1,
    notes        TEXT,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL,
    deleted_at   TEXT
);

CREATE TABLE discounts (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    kind         TEXT NOT NULL CHECK (kind IN ('percentage','fixed')),
    value        INTEGER NOT NULL,
    requires_id  INTEGER NOT NULL DEFAULT 0,
    active       INTEGER NOT NULL DEFAULT 1,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL,
    deleted_at   TEXT
);

CREATE TABLE settings (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE users (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    role       TEXT NOT NULL CHECK (role IN ('staff','admin')),
    pin_hash   TEXT NOT NULL,
    active     INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);

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
    event_date            TEXT,
    arrangement           TEXT NOT NULL CHECK (arrangement IN ('school_pays','students_pay')),
    agreed_amount         INTEGER,
    production_status     TEXT NOT NULL DEFAULT 'to_photoshoot'
                          CHECK (production_status IN ('to_photoshoot','in_progress','shot','in_storage','released')),
    release_mode          TEXT NOT NULL DEFAULT 'batch' CHECK (release_mode IN ('batch','per_student')),
    release_override      INTEGER NOT NULL DEFAULT 0,
    release_override_note TEXT,
    created_at            TEXT NOT NULL,
    updated_at            TEXT NOT NULL,
    deleted_at            TEXT
);

CREATE TABLE orders (
    id                  TEXT PRIMARY KEY,
    package_id          TEXT NOT NULL REFERENCES packages(id),
    school_batch_id     TEXT REFERENCES school_batches(id),
    coverage_type       TEXT NOT NULL CHECK (coverage_type IN ('self_pay','school_covered','sponsored')),
    cust_last_name      TEXT NOT NULL,
    cust_first_name     TEXT NOT NULL,
    cust_middle_initial TEXT,
    cust_course         TEXT,
    cust_section        TEXT,
    cust_batch_year     TEXT,
    cust_contact        TEXT,
    list_price          INTEGER NOT NULL,
    discount_id         TEXT REFERENCES discounts(id),
    discount_name       TEXT,
    discount_kind       TEXT CHECK (discount_kind IN ('percentage','fixed')),
    discount_value      INTEGER,
    discount_amount     INTEGER,
    discount_id_number  TEXT,
    discount_id_name    TEXT,
    discount_applied_by TEXT,
    production_status   TEXT NOT NULL DEFAULT 'to_shoot'
                        CHECK (production_status IN ('to_shoot','shot','in_storage','released')),
    released_at         TEXT,
    released_by         TEXT,
    notes               TEXT,
    created_at          TEXT NOT NULL,
    updated_at          TEXT NOT NULL,
    deleted_at          TEXT
);
CREATE INDEX idx_orders_batch    ON orders(school_batch_id);
CREATE INDEX idx_orders_lastname ON orders(cust_last_name, cust_first_name);
CREATE INDEX idx_orders_prod     ON orders(production_status);

CREATE TABLE contributions (
    id              TEXT PRIMARY KEY,
    order_id        TEXT REFERENCES orders(id),
    school_batch_id TEXT REFERENCES school_batches(id),
    source          TEXT NOT NULL CHECK (source IN ('cash','gcash','school','sponsorship')),
    amount          INTEGER NOT NULL,
    recorded_by     TEXT NOT NULL,
    note            TEXT,
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    deleted_at      TEXT,
    CHECK ((order_id IS NOT NULL) <> (school_batch_id IS NOT NULL))
);
CREATE INDEX idx_contrib_order  ON contributions(order_id);
CREATE INDEX idx_contrib_batch  ON contributions(school_batch_id);
CREATE INDEX idx_contrib_source ON contributions(source);

CREATE TABLE queue_tickets (
    id            TEXT PRIMARY KEY,
    order_id      TEXT NOT NULL REFERENCES orders(id),
    business_date TEXT NOT NULL,
    number        TEXT NOT NULL,
    purpose       TEXT NOT NULL DEFAULT 'shoot' CHECK (purpose IN ('shoot','pickup')),
    lane          TEXT,
    status        TEXT NOT NULL DEFAULT 'waiting'
                  CHECK (status IN ('waiting','called','serving','done','skipped')),
    called_at     TEXT,
    served_by     TEXT,
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL,
    deleted_at    TEXT
);
CREATE INDEX idx_tickets_status ON queue_tickets(business_date, status);

CREATE TABLE queue_counters (
    business_date TEXT NOT NULL,
    lane          TEXT NOT NULL DEFAULT 'main',
    last_number   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (business_date, lane)
);

CREATE TABLE event_log (
    id             TEXT PRIMARY KEY,
    seq            INTEGER,
    type           TEXT NOT NULL,
    aggregate_type TEXT NOT NULL,
    aggregate_id   TEXT NOT NULL,
    occurred_at    TEXT NOT NULL,
    actor          TEXT,
    payload        TEXT NOT NULL,
    version        INTEGER NOT NULL DEFAULT 1,
    synced         INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_events_aggregate ON event_log(aggregate_type, aggregate_id);
CREATE INDEX idx_events_unsynced  ON event_log(synced, seq);
