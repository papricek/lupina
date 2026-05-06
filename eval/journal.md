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
