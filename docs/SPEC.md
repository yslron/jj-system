# JJ — Queue & Kiosk System (Photography Module)

> **Status:** Discovery / draft spec. No app code yet.
> This document captures the shared understanding from planning conversations.
> It is a living reference — expect it to change as we refine.

---

## 1. What this is

A **queue + kiosk system** for JJ's photography services. A customer arrives,
chooses a package, pays (or is checked in), gets a queue number, is photographed,
and later receives their photos. Behind that simple flow, the business needs to
**track money and the photos themselves** through their full lifecycle.

This is the **first module** of a larger JJ platform. It must stand on its own
and not make assumptions that block future modules.

### Guiding principles

| Principle | Meaning |
|---|---|
| **Offline-first** | Runs fully on-site, no internet dependency. Data lives locally. |
| **Sync-ready (later)** | Designed so online sync / multi-location can be added later — but **not built yet**. |
| **One module of many** | Self-contained; part of a bigger JJ system to come. |
| **Configured, not hardcoded** | Packages, prices, and discounts are managed in **Settings**, not baked into code. |

### Rollout

- **Now:** one fixed on-site location, offline.
- **Later:** on-site sync + online (separate conversation).

---

## 2. Two faces of the app

The system has **two distinct surfaces**:

1. **Customer Kiosk** (self-service, locked-down)
   - Customer only: pick package → pay → get queue number.
   - Cannot apply discounts or sponsorship to themselves.

2. **Staff / Admin** (PIN-protected)
   - Manage the queue, mark payments, apply discounts & sponsorship,
     release photos, view all money, configure Settings.

---

## 3. Services

### Studio walk-in
- **Family**
- **Solo**
- **Portraits**

### School photography
Two payment arrangements:
- **School-pays batch** — the school pays JJ in bulk; **no individual payment** at the kiosk.
- **Students-pay-individually** — each student pays for themselves (like a walk-in, but tagged to the school).

---

## 4. The money model

### Coverage type (the context of an order)
- **Self-pay** — the person pays at the kiosk.
- **School-covered** — the school pays in bulk for the batch.
- **Sponsored** — JJ absorbs the cost out of goodwill (full or partial). Admin-only.

### Every order is a 3-layer stack

```
List price            (from the package)
  − Discount          (one only: PWD / Senior / promo)
  = Net due
  filled by contributions, each tagged by source:
      Cash · GCash · School · Sponsorship
  = Settled when contributions ≥ Net due
```

**Worked example**

```
Solo package — list ₱500
  − Senior discount (20%)        −₱100
  = Net due                       ₱400
  ₱200 Cash + ₱200 Sponsorship    ₱400  → settled ✓
```

### Why tag every contribution by source
Keeps four numbers separate and honest in reporting:
- List revenue
- Discounts given
- Sponsorship given (goodwill — ₱0 cash but value recorded)
- Real cash / GCash collected

### Discounts vs. Sponsorship — not the same thing
- **Discount** *lowers the price* (service is genuinely cheaper; money never expected).
- **Sponsorship** *does not lower the price*; full price stands and **JJ pays the gap** (money given away). Recorded at value.

### Discounts
- **Created/managed in Settings** (name + percentage), e.g. "Senior Citizen — 20%", "PWD — 20%", "Holiday Promo — 10%".
- **No stacking** — one discount per order.
- **Applied by staff**, who verify the physical ID.
- PWD/Senior should **log the ID number + name** for legal audit trail (recommended).

### Sponsorship
- **Admin-screen only** (not at the kiosk; editable after the fact).
- Can be **full or partial** (e.g. student pays ₱200, JJ sponsors ₱300).
- Counts toward "settled," so a sponsored person is eligible for release.
- Lives in the **individual-pay** world (walk-in + students-pay-individually).
  A school's inability to pay fully is handled at the **batch** level, not per student.

---

## 5. Two independent lifecycles

Payment status and production status move **independently** and are tracked as
**separate fields** (never one combined status).

### Payment
```
Unpaid → Partial → Paid
```
(Sponsorship and School contributions count toward Paid.)

### Production / fulfillment
```
To-shoot → Shot → In storage → Released
```
- An edit/print step (e.g. Editing → Printing) may be inserted between Shot and
  In storage later — **left flexible for now.**

---

## 6. Release rules

| | Individual order | School batch |
|---|---|---|
| **Release requires** | **Fully settled** (strict) | May release on **partial** payment (intentional override, flagged) |
| **Granularity** | Per person | **Whole-batch** *or* **per-student at the shop** |

Design choice: **every individual always has their own production/release status.**
A whole-batch release is a shortcut that releases everyone in the batch at once.
This supports batch release, per-student pickup, or a mix — without locking in.

---

## 7. School batches

- A **school batch contains many individual people.**
- **School-pays batch:** no individual payments; the school settles the batch.
- Batch has its own payment status (Partial → Paid) and progress
  (To-photoshoot → In progress → Shot → In storage → Released).
- Release may be whole-batch or per-student (see §6).

---

## 8. Open questions (to revisit)

- [ ] Edit/print step between **Shot** and **In storage** — needed? what stages?
- [ ] **Queue mechanics:** one shared line or separate lines (studio vs school, per booth/photographer)?
- [ ] When it's someone's turn and they're **not present** — skip / re-queue / hold?
- [ ] Does the **queue number** cover only the shoot, or also **pickup/release** (a second line)?
- [ ] Roughly **how long is one shoot** (paces the queue)?
- [ ] **Owner's end-of-day view** — exact numbers wanted (sales, count shot, walk-in vs school, sponsored value, outstanding balances).
- [ ] **Kiosk hardware** — customer-operated touchscreen vs staff-operated screen.
- [ ] Peak volumes (dozens vs hundreds) and whether anyone **books ahead**.

---

## 9. Not in scope yet

- Real payment processing (gateway). v1 **records** payments only; staff confirm.
- Online sync / multi-location.
- Other (non-photography) JJ modules.
