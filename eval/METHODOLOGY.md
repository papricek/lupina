# Eval Dataset Methodology

How to transform real EDC meter readings into the one-line Czech descriptions used as ground-truth labels for Lupina's training loop.

## The problem

We have real 15-minute EDC readings scraped from the Czech national portal. For each eval entry we need a single Czech sentence that a customer *could plausibly have said* to describe that installation — the kind of input Lupina's `parse_description` receives in production.

The description must be **derivable from the data** (not from external knowledge about the customer), **colloquial** (matching `README.md` examples), and **reproducible** (two annotators on the same data should converge).

## Inputs per entry

Each dataset folder `eval/dataset/<id>/` contains:

- `real.csv` — real EDC file in Lupina format (`Datum;Cas od;Cas do;IN-<ean>-D;OUT-<ean>-D`)
- `metadata.json` — `{ kind, capacity_kwp, month, year, days_in_month, ean_hash }`
- `aggregates.json` — precomputed stats (below) so annotators don't re-derive them

## Aggregates (precomputed)

Generated once by the extraction script, stored alongside `real.csv`:

```json
{
  "total_kwh_in": 1234.5,
  "total_kwh_out": 567.8,
  "peak_15min_kwh": 8.2,
  "peak_kw": 32.8,
  "workday_hourly_avg_out": [0.0, 0.0, ..., 24 floats],
  "weekend_hourly_avg_out": [0.0, 0.0, ..., 24 floats],
  "workday_hourly_avg_in": [24 floats],
  "weekend_hourly_avg_in": [24 floats],
  "per_weekday_daily_total_out": {"0": 12.3, "1": 4.5, ...},  // 0=Sun..6=Sat
  "per_weekday_daily_total_in": {"0": ..., "6": ...},
  "zero_hours_workday": [7, 8, 9, 10, 11, 12, 13, 14],  // hours with <5% of peak
  "zero_hours_weekend": [],
  "bimodal": false,                                      // two distinct peaks?
  "flat_daytime": false,                                 // near-constant 8-17?
  "saturday_vs_sunday_delta": 0.15                       // relative diff
}
```

## Analysis framework (6 steps)

Work through these in order. Each step narrows the description.

### Step 1 — Kind and headline numbers

- **Production** (has `final` > 0 values): headline = `{capacity} kWp, přetoky {total_out_mwh:.0f} MWh ročně`
- **Consumption** (only `original` > 0): headline = `spotřeba {total_in_mwh:.0f} MWh ročně`

Scale monthly total to yearly: `yearly ≈ monthly × (1 / Lupina::SolarModel::MONTHLY_PRODUCTION_SHARE[month])` for production, or `yearly ≈ monthly × 12 / days_fraction` for consumption.

### Step 2 — Export/consumption ratio (production only)

Compute `ratio = yearly_surplus / (capacity × 1000)`.

- `> 0.85` → minimal local consumption, full-export style
- `0.50 – 0.85` → partial consumption, some pattern
- `0.20 – 0.50` → heavy consumption, export only outside peak
- `< 0.20` → very heavy consumption, export in narrow window

This ratio determines how "loaded" the description should be with consumption detail.

### Step 3 — Workday pattern classification

Look at `workday_hourly_avg_out` (production) or `workday_hourly_avg_in` (consumption).

| Shape | Classification | Czech phrase |
|---|---|---|
| All ~equal to weekend | "same every day" | `pořád stejně` / `stejný profil celý týden` |
| Zero block X–Y within solar hours | "work X–Y" | `jede od X do Y`, `makáme X-Y` |
| Reduced vs weekend, no zero block | "partial occupancy" | `přes týden vše sežereme` |
| Near-full export, weekend reduced | "empty workdays" | `přes den nikdo doma` |
| Bimodal dip | "morning + evening occupancy" | `dojíme ráno a večer` |
| Noon dip only | "lunch break" | `max polední pauza` |

### Step 4 — Weekend pattern classification

Compare `weekend_hourly_avg_*` to `workday_hourly_avg_*`:

- Nearly identical → weekend clause not needed (or `víkend stejně`)
- Weekend higher (production) → `víkend plné přetoky`
- Weekend lower (consumption side of production) → `víkend spotřeba`
- Saturday and Sunday differ markedly → `sobota dopoledne, neděle zavřeno` or similar

### Step 5 — Special features (optional clause)

Include at most one, only if clearly present in the data:

- Night-only operation (consumption peaks 22–06) → `nocní směna`
- Milking dips at specific hours → `dojíme 5-8 a 17-19`
- Lunch break → `max polední pauza`
- Only weekends active → `jezdíme jen o víkendech`

### Step 6 — Assemble the line

Template:
```
{headline}, {workday phrase}[, {weekend phrase}][, {special feature}]
```

Max ~15 words. Drop clauses if the pattern is simple.

## Style rules

**Match `README.md` examples.** Colloquial, lowercase, no quotation marks, no technical jargon. Common verbs: `jede`, `makáme`, `sežereme`, `vypnou mašiny`, `jezdíme`, `dojíme`.

**Do NOT invent business type.** Unless the data unambiguously implies it (e.g. consumption spike 3–11 am daily → bakery is *plausible*, not certain), describe the *behavior* not the *business*. `velké ráno, jinak nízká spotřeba` is safer than `pekárna`.

**Do NOT reference external knowledge.** Don't use `rodinný dům` unless the capacity (≤15 kWp) AND daily shape (evening/morning residential peaks) both support it. Better: `30 kWp, přetoky 12 MWh ročně, přes den prázdno, víkend spotřeba`.

**Prefer concrete times.** If the zero block starts at hour 7 and ends at hour 15, write `jede od 7 do 15`, not `jede přes den`.

**One line only.** Multi-sentence descriptions break the input assumption.

## Anti-patterns

- ❌ `pekárna, spotřeba 25 MWh ročně` — guessing business
- ❌ `lidi přijdou domů v 17:03` — over-specifying noise
- ❌ `solar plant with high export ratio` — English, not colloquial
- ❌ `100 kWp, přetoky 30 MWh ročně` — headline only, no pattern clause (too thin)
- ✅ `100 kWp, přetoky 30 MWh ročně, přes týden vše sežereme, max polední pauza`

## Reproducibility check

For each description, ask:
1. Could I re-derive this phrasing from `aggregates.json` alone without peeking at the CSV? (If no, the description encodes knowledge the data doesn't.)
2. Would another annotator reading the same aggregates write something with the same *classification* (same workday category, same weekend category, same special feature)? (Different wording is fine — classification must match.)

## Worker instructions (for the annotator agent)

Given `eval/dataset/<id>/`:

1. Read `metadata.json` and `aggregates.json`
2. Execute the 6-step framework above
3. Write `description.txt` — one line, Czech, following style rules
4. Write `reasoning.txt` — short bullet list of classification decisions:
   ```
   - kind: production, capacity 80 kWp, yearly export ~35 MWh, ratio 44%
   - workday: zero block 7-14 (8h), export 15+
   - weekend: full solar curve, no reduction
   - special: none
   - → "pila jede 7-15, pak vše do sítě, víkend plné přetoky"
   ```
5. Do NOT read `real.csv` unless the aggregates are ambiguous — the aggregates are the summary you need.

## Human review

Every machine-generated description should be human-reviewed before landing in the eval set. The review check:

- Does it follow style rules?
- Does it match the classification in `reasoning.txt`?
- Would the customer have plausibly said this?
- Does it avoid invented context?

Descriptions that fail review go back for rewrite. Descriptions that pass are committed with `description_reviewed: true` in metadata.
