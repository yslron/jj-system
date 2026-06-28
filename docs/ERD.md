# JJ — Entity Relationship Diagram (Photography Module)

> Companion to `DATA-MODEL.md`. Renders as a diagram on GitHub.
> Crow's-foot notation: `||` = exactly one, `|o` = zero or one, `o{` = zero or many.

```mermaid
erDiagram
    SCHOOL        ||--o{ SCHOOL_BATCH : "runs"
    SCHOOL_BATCH  |o--o{ ORDER        : "contains"
    PACKAGE       ||--o{ ORDER        : "sold as"
    DISCOUNT      |o--o{ ORDER        : "applied to (snapshot)"
    ORDER         ||--o{ CONTRIBUTION : "paid by"
    SCHOOL_BATCH  ||--o{ CONTRIBUTION : "paid by (school-pays)"
    ORDER         ||--o{ QUEUE_TICKET : "queued as"

    SCHOOL {
        uuid   id PK
        string name
        string contactPerson
        string contactInfo
    }

    SCHOOL_BATCH {
        uuid   id PK
        uuid   schoolId FK
        string label
        date   eventDate
        enum   arrangement "school_pays | students_pay"
        money  agreedAmount
        enum   paymentStatus "derived"
        enum   productionStatus
        enum   releaseMode "batch | per_student"
        bool   releaseOverride
    }

    PACKAGE {
        uuid   id PK
        string name
        enum   serviceType "family | solo | portraits | school"
        money  listPrice
        bool   active
    }

    DISCOUNT {
        uuid   id PK
        string name
        enum   kind "percentage | fixed"
        number value
        bool   requiresId
        bool   active
    }

    ORDER {
        uuid   id PK
        uuid   packageId FK
        uuid   schoolBatchId FK "nullable"
        uuid   discountId FK "nullable, snapshotted"
        json   customer "last,first,MI,course,section,batchYear,contact"
        money  listPrice "snapshot"
        money  netDue "derived"
        enum   coverageType "self_pay | school_covered | sponsored"
        enum   paymentStatus "derived"
        enum   productionStatus "to_shoot | shot | in_storage | released"
    }

    CONTRIBUTION {
        uuid   id PK
        uuid   orderId FK "XOR batch"
        uuid   schoolBatchId FK "XOR order"
        enum   source "cash | gcash | school | sponsorship"
        money  amount
        string recordedBy
    }

    QUEUE_TICKET {
        uuid   id PK
        uuid   orderId FK
        string number "per-day, e.g. A-014"
        enum   purpose "shoot | pickup"
        enum   status "waiting | called | serving | done | skipped"
    }
```

## Relationships in words

- A **School** runs many **School Batches**.
- A **School Batch** contains many **Orders** (an Order may belong to zero or one batch — walk-ins have none).
- A **Package** is sold as many **Orders**; each Order has exactly one Package.
- A **Discount** may apply to many **Orders**; each Order has zero or one discount (snapshotted onto the Order).
- An **Order** is paid by many **Contributions**; a **School Batch** also holds Contributions (for `school_pays`).
- A **Contribution** belongs to **exactly one** of Order *or* School Batch (XOR — not both). Mermaid can't draw the XOR, hence the note.
- An **Order** is queued as many **Queue Tickets** (one `shoot` now; a future `pickup` ticket is why this is one-to-many, not one-to-one).

## Notes

- **Settings entities** (`PACKAGE`, `DISCOUNT`) are configured by staff; everything
  else is operational data created during a day.
- **Derived fields** (`netDue`, `paymentStatus`, batch `paymentStatus`) are computed,
  not stored as source of truth — see `DATA-MODEL.md` §6.
- The diagram shows key attributes only; full field lists live in `DATA-MODEL.md`.
