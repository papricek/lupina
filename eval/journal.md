# Autoresearch journal — V3 dataset

RUNNING BEST: 0.3255 at 2026-05-06T00:00 (V3 baseline, unmodified lupina at this commit)

## V3 dataset

8 entries × 4 description tiers × {2026-03, 2026-04} from `learning_algo_V3.xlsx` =
**32 cases per iteration**. Tiers: `popis`, `popis_2`, `popis_laik`, `popis_zkuseny`.
Real CSVs from `edc_readings`, filtered to ≥2800 rows AND total_out ≥ capacity_kwp × 5 kWh.
Yearly surplus = xlsx "Přetoky (MWh)" × 1000, capped at capacity_kwp × 999.

The yearly Přetoky figure in the xlsx for several rows diverges ~10× from
measured monthly export (e.g. V3_08 claims 25 MWh/yr but April measured 256 kWh).
This is real signal, not a bug — most of the algorithm's `daily_total_mape` raw
score (~5.4) comes from this gap and is capped at 1.0 weighted.

## Component baseline (raw → weighted)

| Component | Raw | Weighted | Headroom |
|---|---|---|---|
| daily_total_mape    | 5.41 | 0.250 (capped) | shrinking raw below 1.5 starts moving the score |
| hourly_shape_mae    | 0.54 | 0.082 | -0.04 if raw → 0.30 |
| peak_time_delta     | 1.80 | 0.015 | small contribution |
| weekday_ratio_error | 0.37 | 0.028 |  |
| autocorr_distance   | 0.09 | 0.004 | tiny |
| variance_ratio_error| 1.25 | 0.025 |  |

## Per-entry baseline (lower = better)

| Entry | kWp | Month | Composite |
|---|---|---|---|
| V3_01 (AGRO L)       |  97 | 2026-04 | 0.487 |
| V3_02 (Nářadí)       | 100 | 2026-04 | 0.433 |
| V3_03 (Southproject) |  96 | 2026-04 | 0.406 |
| V3_04 (Vachta)       |   3 | 2026-03 | 0.182 |
| V3_05 (Vachta)       |   3 | 2026-04 | 0.242 |
| V3_06 (Kumžák)       |  10 | 2026-03 | 0.142 |
| V3_07 (Kumžák)       |  10 | 2026-04 | 0.116 |
| V3_08 (JS KOVO)      |  30 | 2026-04 | 0.596 |

The xlsx-vs-measured discrepancy is concentrated in V3_01, V3_02, V3_03, V3_08.
V3_06 and V3_07 (Kumžák) are the cleanest cases.

## Per-tier baseline

| Tier           | Composite |
|---|---|
| popis          | 0.325 |
| popis_2        | 0.328 |
| popis_laik     | 0.323 |
| popis_zkuseny  | 0.327 |

Tiers are within 0.01 of each other at baseline — the parser handles all 4 styles
roughly equally. No tier is currently a weak point.

---

## Iterations

## iter 001 — 2026-05-06T00:30 — REJECTED
Hypothesis: variance_ratio_error raw=1.25 means synth variance is ~3.5× real (e^1.25). Narrow `assign_daily_factors` from `0.1 + rand * 1.8` (range 0.1–1.9, var≈0.27) → `0.5 + rand * 1.0` (range 0.5–1.5, var≈0.083) to bring synth variance down toward real.
Diff: edc_generator.rb:100 (one line)
Score before: 0.3255 (dmape=5.41, shape=0.54, peak=1.80, ratio=0.37, acf=0.09, var=1.25)
Score after:  0.3352 (dmape=5.46, shape=0.54, peak=1.80, ratio=0.36, acf=0.09, var=1.36)
Delta: +0.0097
Why: Overshot. Narrowing too aggressively crossed the synth_var = real_var point on at least some entries, so |log(synth/real)| flipped sign and grew.

## iter 002 — 2026-05-06T00:35 — REJECTED
Hypothesis: hourly_shape_mae raw=0.54 weighted=0.082 is biggest movable component. Soften morning of solar envelope (3.5 → 3.0) to widen daytime curve, expecting to better match V3_03/V3_05/V3_07 which describe broad afternoon export.
Diff: edc_generator.rb:109 (3.5 → 3.0)
Score before: 0.3255 (shape=0.54)
Score after:  0.3262 (shape=0.55)
Delta: +0.0007
Why: Marginal regression — softening morning shifts profile mass and may have hurt V3_06/V3_07 (the well-fitting cases) more than it helped the misfitting ones.

## iter 003 — 2026-05-06T00:42 — REJECTED
Hypothesis: variance_ratio_error 1.25 may mean synth variance still too high. Eliminate per-day random factor (constant 1.0); intra-day noise still provides ±15% variance.
Diff: edc_generator.rb:100 (`0.1 + rand * 1.8` → `1.0`)
Score before: 0.3255 (var=1.25)
Score after:  0.3920 (var=3.67)
Delta: +0.0665
Why: Direction wrong — real_var is HIGHER than current synth_var, not lower. Constant daily_factor collapses synth daily-total variance well below real, so |log(synth/real)| explodes negative. Important learning: synth variance was already on the SAME side of real (lower side) at baseline, not the high side I assumed.

## iter 004 — 2026-05-06T00:48 — REJECTED
Hypothesis: optimum daily_factor variance is between iter 001's 0.083 and original 0.27. Try `0.3 + rand * 1.4` (var=0.163, ~60% of original).
Diff: edc_generator.rb:100 (one line)
Score before: 0.3255 (var=1.25)
Score after:  0.3282 (var=1.24)
Delta: +0.0027
Why: var_ratio improved tiny bit (-0.01 raw) but other components shifted up slightly (dmape, shape, ratio). Net worse. Confirms that this knob has diminishing returns and interacts non-trivially with other components.

## Pause after 4 rejected iterations

The composite is dominated by `daily_total_mape` capped at 0.250 weighted (raw 5.41, normalizer 1.5). Generator-only changes can shrink at most the remaining ~0.075 weighted from the other 5 components, and those interact with each other in non-linear ways (iter 001/004). To unlock real movement we need to address the cap — meaning push dmape raw below 1.5.

The dataset's underlying issue: 4 of 8 entries (V3_01, V3_02, V3_03, V3_08) have xlsx-yearly that's ~10× higher than measured monthly suggests. No knob in `edc_generator.rb` can compensate. Options are:
- A) Add a self-consumption discount inside `monthly_surplus_kwh` driven by a parser hint (e.g., parser reads "domácnost", "vlastní spotřeba minimální", or "skoro 6 MWh" specific monthly claims and emits a `monthly_surplus_override_kwh` that EdcGenerator uses if present).
- B) Accept the cap as a fixed background and only chase the remaining 0.075 weighted via solar/profile/parser tweaks (slow, ceiling around composite 0.25).
- C) Drop the worst 4 entries from V3 — but then we're not really testing the algorithm's robustness to messy descriptions.

