# JJ — Data Model (Photography Module)

> **Status:** Draft blueprint. No app code yet. Companion to `SPEC.md`.
> Field types are technology-neutral. The store will be local (offline-first);
> SQLite-style tables or a document store both map cleanly onto this.

---

## 0. Conventions (so future sync just works)

Every record carries these, for free, from day one:

| Field | Type | Why |
|---|---|---|
| `id` | UUID | Globally unique → no collisions when multiple devices sync later. |
| `createdAt` | timestamp | Audit + ordering. |
| `updatedAt` | timestamp | Last-write-wins basis for future sync. |
| `deletedAt` | timestamp \| null | **Soft delete** — never hard-delete; sync needs to see tombstones. |

**Price snapshots:** orders copy the price/discount values *at the time of sale*.
Changing a package price in Settings later must **not** rewrite old orders.

---

## 1. Entity overview

```
Settings                         Operations
--------                         ----------
Package  ──────────────┐
Discount ──────┐       │
               │       └──► Order ───────┬──► Contribution
School ──► SchoolBatch ──┘  (per person) ├──► QueueTicket
                            ▲            └──► (discount snapshot, inline)
                            │
            SchoolBatch ────┘  (an order may belong to a batch)
            also has ──► Contribution (batch-level, for school-pays)
```

- **Order** is the spine: one per person being photographed (walk-in *or* school student).
- **SchoolBatch** groups many orders and can hold its own batch-level payments.
- **Contribution** can attach to *either* an Order or a SchoolBatch.

---

## 2. Settings entities (configured, not hardcoded)

### Package
The sellable services. Edited in Settings.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | string | e.g. "Solo", "Family", "Graduation A" |
| `serviceType` | enum | `family` \| `solo` \| `portraits` \| `school` |
| `listPrice` | money | Default price; snapshotted onto orders. |
| `active` | bool | Hide retired packages without deleting. |
| `notes` | string | Optional (inclusions, # of prints, etc.). |

### Discount
Defined in Settings; applied by staff. **One per order, no stacking.**

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | string | e.g. "Senior Citizen", "PWD", "Holiday Promo" |
| `kind` | enum | `percentage` \| `fixed` |
| `value` | number | 20 (%) or 100 (₱), per `kind`. |
| `requiresId` | bool | If true, applying it **forces** an ID number/name (PWD/Senior). |
| `active` | bool | |

---

## 3. School entities

### School

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | string | |
| `contactPerson` | string | Optional |
| `contactInfo` | string | Optional (phone/email) |
| `notes` | string | Optional |

### SchoolBatch
One shoot engagement for a school. Groups many orders.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `schoolId` | UUID → School | |
| `label` | string | e.g. "Batch 2026 — Grade 12" |
| `eventDate` | date | Optional |
| `arrangement` | enum | `school_pays` \| `students_pay` |
| `agreedAmount` | money \| null | For `school_pays`: total billed to the school. |
| `paymentStatus` | enum (derived) | `unpaid` \| `partial` \| `paid` — from batch Contributions vs `agreedAmount`. |
| `productionStatus` | enum | `to_photoshoot` \| `in_progress` \| `shot` \| `in_storage` \| `released` |
| `releaseMode` | enum | `batch` \| `per_student` (how photos get handed over). |
| `releaseOverride` | bool | True if released while not fully paid (intentional). |
| `releaseOverrideNote` | string \| null | Why (the internal agreement). |

> **Rule:** a `school_pays` batch has **no order-level contributions**; its money
> lives in batch-level Contributions. A `students_pay` batch leaves payment to
> each student's Order.

---

## 4. Order — the per-person spine

One row per person being photographed. Walk-in customers **and** school students.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `customer` | object | Structured identity + contact (see below). |
| `packageId` | UUID → Package | |
| `listPrice` | money | **Snapshot** of package price at sale time. |
| `coverageType` | enum | `self_pay` \| `school_covered` \| `sponsored` |
| `schoolBatchId` | UUID → SchoolBatch \| null | Set if part of a school batch. |
| `discount` | object \| null | Inline **snapshot** (see below). |
| `netDue` | money (derived) | `listPrice − discount.amount`. |
| `paymentStatus` | enum (derived) | `unpaid` \| `partial` \| `paid` (see §6). |
| `productionStatus` | enum | `to_shoot` \| `shot` \| `in_storage` \| `released` |
| `releasedAt` | timestamp \| null | |
| `releasedBy` | string \| null | Staff who released. |
| `notes` | string \| null | |

### Customer identity (inline `customer` object on the Order)
Structured so rosters sort/print as `Lastname, Firstname M.I.`.
`course` and `batchYear` apply to **school orders only**; they stay null for walk-ins.

| Field | Type | Notes |
|---|---|---|
| `lastName` | string | Required. Primary sort key for rosters. |
| `firstName` | string | Required. |
| `middleInitial` | string \| null | Single letter (e.g. "D"). Optional. |
| `course` | string \| null | School only (e.g. "BSIT"). |
| `section` | string \| null | School only (e.g. "4-A"). |
| `batchYear` | string \| null | School only (e.g. "2026"). May default from `SchoolBatch`. |
| `contact` | string \| null | Phone / email. Optional. For pickup/release notice. |

> **Display helper:** `"{lastName}, {firstName} {middleInitial}."` —
> middle initial omitted when null. Walk-in customers just fill last/first.

### Discount snapshot (inline on the Order)
Copied at apply-time so later Settings edits don't rewrite history.

| Field | Type | Notes |
|---|---|---|
| `discountId` | UUID → Discount | Reference to the source. |
| `name` | string | Snapshot ("Senior Citizen"). |
| `kind` / `value` | enum / number | Snapshot of the rule. |
| `amount` | money | Computed ₱ amount taken off. |
| `idNumber` | string \| null | Required if `requiresId`. |
| `idName` | string \| null | Required if `requiresId`. |
| `appliedBy` | string | Staff who verified. |

---

## 5. Contribution — money in, tagged by source

One row per payment event. Attaches to an Order **or** a SchoolBatch (exactly one).

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `orderId` | UUID → Order \| null | Set for individual payments. |
| `schoolBatchId` | UUID → SchoolBatch \| null | Set for school-pays batch payments. |
| `source` | enum | `cash` \| `gcash` \| `school` \| `sponsorship` |
| `amount` | money | |
| `recordedBy` | string | Staff. |
| `note` | string \| null | e.g. reference #, agreement note. |

> **Why a table, not a number:** partial sponsorship = two rows
> (`cash ₱200` + `sponsorship ₱300`). Reporting sums by `source` to keep
> *list revenue / discounts / sponsorship value / real cash* all separable.

---

## 6. Derived values & rules

These are **computed**, never stored as the source of truth.

### `netDue`
```
netDue = listPrice − (discount ? discount.amount : 0)
```

### `paymentStatus` (Order)
```
if coverageType == school_covered:
    inherit from schoolBatch.paymentStatus
else:
    paid    = sum(contributions where orderId == this.id)   // cash+gcash+sponsorship
    if paid <= 0           → unpaid
    else if paid <  netDue → partial
    else                   → paid
```
Sponsorship counts toward `paid`. A fully-sponsored order is `paid` with ₱0 cash.

### Release eligibility
```
Individual order (self_pay | sponsored):
    eligible  ⇔  paymentStatus == paid          (STRICT)

School-covered order:
    eligible  ⇔  batch.paymentStatus == paid
                 OR batch.releaseOverride == true   (intentional partial release)
```

### Batch `paymentStatus` (school_pays)
```
paid = sum(contributions where schoolBatchId == batch.id)
vs batch.agreedAmount → unpaid / partial / paid
```

---

## 7. QueueTicket

The customer-facing number. Kept as its own entity so a **second queue**
(e.g. pickup/release) can be added later without reshaping anything.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `number` | string | Human-facing, sequential **per day** (e.g. `A-014`). |
| `orderId` | UUID → Order | The person being served. |
| `purpose` | enum | `shoot` (now) \| `pickup` (future). |
| `status` | enum | `waiting` \| `called` \| `serving` \| `done` \| `skipped` |
| `calledAt` | timestamp \| null | |
| `servedBy` | string \| null | Photographer/booth. |

> **Open:** one shared line vs. separate lines (per booth / studio vs school),
> and skip/re-queue/hold behavior — see `SPEC.md` §8. `purpose` + a future
> `lane` field cover these without a redesign.

---

## 8. Reporting — falls out of the model for free

| Number | How it's computed |
|---|---|
| Real cash collected | Σ Contributions where `source ∈ {cash, gcash}` |
| Sponsorship given | Σ Contributions where `source = sponsorship` |
| Discounts given | Σ `order.discount.amount` |
| School-paid | Σ Contributions where `source = school` |
| List revenue | Σ `order.listPrice` |
| Shot today | count Orders where `productionStatus ≥ shot` |
| Awaiting release | Orders eligible but `productionStatus = in_storage` |
| Outstanding balance | Σ (`netDue − paid`) where `paymentStatus = partial` |

---

## 9. Still open (carried from SPEC §8)

- Edit/print sub-stages between `shot` and `in_storage`.
- Queue: shared vs multiple lanes; not-present behavior; pickup as a second queue.
- Whether `pickup` queue is needed in v1.
- Exact owner end-of-day dashboard.
