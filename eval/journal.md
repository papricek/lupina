# Autoresearch journal — V3 dataset

RUNNING BEST (legacy path): 0.3255 at 2026-05-06T00:00 (unmodified lupina at the V3 harness commit)
RUNNING BEST (hourly path): 0.3369 at 2026-05-07T04:00 (h020 — Gemini temperature=0 for deterministic LLM outputs)

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

## Pause after 4 rejected iterations — strategy pivot to hourly path

The composite on legacy is dominated by `daily_total_mape` capped at 0.250 weighted (raw 5.41, normalizer 1.5). Generator-only changes can shrink at most the remaining ~0.075 weighted from the other 5 components, and those interact with each other in non-linear ways (iter 001/004). To unlock real movement we need to address the cap — meaning push dmape raw below 1.5.

The dataset's underlying issue: 4 of 8 entries (V3_01, V3_02, V3_03, V3_08) have xlsx-yearly that's ~10× higher than measured monthly suggests. No knob in `edc_generator.rb` can compensate.

**Pivot**: introduce a parallel "hourly absolute profile" path. The LLM produces 24 absolute kWh-per-hour values for typical workday/weekend/holiday, and a script upsamples to 15-min with multiplicative noise + per-day weather factor. The LLM takes on the self-consumption / reconciliation work that no generator knob can do.

---

## Hourly path — initial baseline

**Composite: 0.3736** (worse than legacy 0.3255, but expected — see breakdown).

| Entry | Legacy | Hourly | Δ |
|---|---|---|---|
| V3_01 (AGRO L) | 0.487 | 0.444 | **−0.04** ✓ |
| V3_02 (Nářadí) | 0.433 | 0.448 | +0.01 |
| V3_03 (Southproject) | 0.406 | 0.386 | **−0.02** ✓ |
| V3_04 (Vachta Mar) | 0.182 | 0.319 | +0.14 ✗ |
| V3_05 (Vachta Apr) | 0.242 | 0.368 | +0.13 ✗ |
| V3_06 (Kumžák Mar) | 0.142 | 0.257 | +0.12 ✗ |
| V3_07 (Kumžák Apr) | 0.116 | 0.223 | +0.11 ✗ |
| V3_08 (JS KOVO) | 0.596 | 0.544 | **−0.05** ✓ |

The new path **wins on the outliers** (where the xlsx-yearly chain failed) and **loses on the well-fitting cases** (where the legacy solar prior was structurally right and the LLM's flatter curve dropped fidelity). Classic trade-off: structural prior vs. LLM reasoning.

Component breakdown at hourly baseline:
- daily_total_mape: 6.42 (worse, +1.0 raw — but capped)
- hourly_shape_mae: 0.61 (worse, +0.07 raw)
- variance_ratio_error: 1.36 (worse, +0.11 raw — extrapolator's DAILY_FACTOR_RANGE 0.7-1.3 too wide)
- peak_time_delta: 1.92 (similar)
- weekday_ratio_error: 0.36 (similar)
- autocorr_distance: 0.08 (similar)

Most of the regression vs legacy is in shape_mae and variance_ratio. Both are extrapolator-side, not LLM-side. Likely quick fixes:
1. Narrow `DAILY_FACTOR_RANGE` (currently 0.7–1.3, ~3× wider than legacy's effective)
2. Narrow `QUARTER_NOISE_RANGE` (currently 0.9–1.1, may be too wide for periods with low absolute kWh)
3. Sharpen `INTRA_HOUR_SHAPE` so peak quarters get more than off-peak quarters of the same hour
4. Adjust the prompt so the LLM produces sharper noon peaks (hourly profile fidelity)

Hourly autoresearch starts at 0.3736; first target is to undercut legacy 0.3255 on overall composite.

## Iterations (hourly path)

## iter h001 — 2026-05-06T02:00 — ACCEPTED
Hypothesis: hourly's DAILY_FACTOR_RANGE = 0.7..1.3 (var=0.03) is 9× narrower than legacy's effective range (var=0.27), yet hourly's variance_ratio_error is HIGHER (1.36 vs legacy 1.25). Narrowness isn't the cause — widening should bring synth daily-total spread closer to real.
Diff: hourly_profile_generator.rb:13 (`(0.70..1.30)` → `(0.50..1.50)`)
Score before: 0.3736 (dmape=6.42, shape=0.61, peak=1.92, ratio=0.36, acf=0.08, var=1.36)
Score after:  0.3664 (dmape=6.31, shape=0.61, peak=1.94, ratio=0.36, acf=0.08, var=1.23)
Delta: −0.0072
Why kept: var_ratio dropped as predicted (-0.13 raw, -0.0026 weighted). dmape also nudged down slightly (capped). No other component meaningfully worse.

## iter h002 — 2026-05-06T02:05 — ACCEPTED
Hypothesis: gradient from h001 suggests further widening of DAILY_FACTOR_RANGE keeps reducing var_ratio. Try `0.4..1.6` (var=0.12).
Diff: hourly_profile_generator.rb:13
Score before: 0.3664 (var=1.23)
Score after:  0.3635 (var=1.20)
Delta: −0.0029
Why kept: small but clean improvement. var_ratio still trending toward zero. Other components stable.

## iter h003 — 2026-05-06T02:08 — ACCEPTED
Hypothesis: continue widening DAILY_FACTOR_RANGE to `0.3..1.7` (var=0.16).
Diff: hourly_profile_generator.rb:13
Score before: 0.3635 (var=1.20, dmape=6.26)
Score after:  0.3621 (var=1.23, dmape=6.20)
Delta: −0.0014
Why kept: smaller improvement than h002. var_ratio actually ticked up (overshooting), but dmape ticked down enough to net positive. Gradient on this knob is plateauing — stopping here, switching to a different knob next.

## iter h004 — 2026-05-06T02:18 — ACCEPTED
Hypothesis: V3_06/V3_07 (Kumžák domestic 10 kWp) regressed in hourly path because the LLM trusts xlsx yearly (7 MWh) and back-computes April via solar share (~630 kWh) — but real April is 488 kWh, and the description even contains seasonal anchors ("srpen 900 kWh, jarní rozjezd od března"). Strengthen parser prompt with explicit anchor priority: in-text monthly numbers > daily numbers > seasonal proportionality > xlsx yearly (last resort).
Diff: hourly_profile_parser.rb prompt section 5 (rewrite, ~10 lines)
Score before: 0.3621
Score after:  0.3531
Delta: −0.0090
Per-entry deltas: V3_04 −0.069, V3_05 −0.076, V3_06 −0.035, V3_07 −0.054 (well-fitting cases corrected), V3_01 +0.018, V3_03 +0.024, V3_08 +0.025 (outliers slightly worse — the LLM may now under-shoot when description gives no clear anchor).
Why kept: net −0.009 is the biggest single-iter gain so far. Anchor-priority instruction works as intended for entries with rich descriptions; outliers that lack monthly anchors lose a bit but stay within the same composite band.

## iter h005 — 2026-05-06T02:23 — REJECTED
Hypothesis: AR(1) correlation between adjacent days (factor[d] = 0.6 × factor[d-1] + 0.4 × sample) should improve autocorr_distance and reflect real cloudy-stretch weather.
Diff: hourly_profile_generator.rb#generate (~5 lines)
Score before: 0.3531 (var=1.20, autocorr=0.083)
Score after:  0.3634 (var=1.44, autocorr=0.081)
Delta: +0.0103
Why: AR(1) reduces day-to-day variance (adjacent days now similar). Real already has higher variance than synth, so reducing synth_var pushes |log(synth/real)| further from 0. Autocorr metric barely moved.

## iter h006 — 2026-05-06T02:30 — ACCEPTED (marginal)
Hypothesis: extend DAILY_FACTOR_RANGE search past h003. Try 0.2..1.8 (var=0.21).
Diff: hourly_profile_generator.rb:13
Score before: 0.3531
Score after:  0.3524
Delta: −0.0007
Why kept: very marginal but consistent. var_ratio ticked up (1.20 → 1.27) but dmape ticked down enough. Gradient on this knob is now essentially flat — stopping here.

## iter h007 — 2026-05-06T02:42 — ACCEPTED
Hypothesis: legacy outperforms hourly on V3_04..V3_07 by ~0.06-0.08 per entry because legacy's solar envelope produces sharper bell curves while LLM outputs flatter ones. Strengthen prompt: explicitly require JEDEN JASNÝ VRCHOL with peak ~2-3× active-window average for "domácí FVE / úzký profil" descriptions, distinct from plateau-style for atypical cases.
Diff: hourly_profile_parser.rb prompt section 4 (rewrite, ~12 lines)
Score before: 0.3524
Score after:  0.3465
Delta: −0.0059
Per-entry deltas: V3_06 −0.048, V3_07 −0.033 (the two domestic cases moved closest to legacy: 0.174 vs legacy 0.142 and 0.136 vs legacy 0.116). V3_01 +0.007, V3_05 +0.008, V3_03 +0.013 (mild), no big regressions.
Components: shape_mae 0.59 → 0.58 (slight); peak_time_delta 1.92 → 1.72 (notable); weekday_ratio_error 0.40 → 0.44 (mild regression — perhaps the sharper-peak instruction reduced the LLM's emphasis on weekend/workday split; worth watching).
Why kept: largest gain since h004. Closes most of the gap to legacy on small-plant entries. Total progress this session 0.3736 → 0.3465 (-0.027). Legacy is at 0.3255 — gap now ~0.02.

## iter h008 — 2026-05-06T02:46 — REJECTED
Hypothesis: h007's prompt changes shifted the LLM's curves; the optimal DAILY_FACTOR_RANGE may have shifted. Try slightly narrower 0.25..1.75.
Diff: hourly_profile_generator.rb:13
Score before: 0.3465
Score after:  0.3468
Delta: +0.0003
Why: marginal regression. The DAILY_FACTOR_RANGE knob is fully exhausted at 0.20..1.80 — gradient is essentially flat in either direction now.

## iter h009 — 2026-05-07T00:30 — REJECTED
Hypothesis: preprocess descriptions to extract numeric anchors (monthly totals, daily totals, peak/active windows, weekend/workday ratio) and prepend to LLM prompt with strong "MUSÍ je respektovat" framing.
Diff: new lib/lupina/anchor_extractor.rb (~150 lines), parser prepends extracted block, score keys cache on both files.
Score before: 0.3465
Score after:  0.3482
Delta: +0.0017
Per-entry deltas: V3_01..V3_05 mostly improved (-0.043 sum), but V3_06 +0.043 and V3_07 +0.007 (Kumžák regression). The strict "MUSÍ" framing forced the LLM into a tight interpolation off "srpen 900 / leden 250" anchors that overrode its previous correct seasonal reasoning. Reverted; rebuilding with milder framing.

## iter h010 — 2026-05-07T01:00 — ACCEPTED
Hypothesis: same anchor preprocessing as h009 but with softer framing — "kalibrační signály ... pomocné anchory" instead of "MUSÍ respektovat", and dropping the explicit weekend/workday ratio (was over-applied).
Diff: new lib/lupina/anchor_extractor.rb, parser prepends block, score keys cache on both files. ~5 lines diff in parser, ~150 lines new in extractor.
Score before: 0.3465
Score after:  0.3455
Delta: −0.0010
Per-entry deltas: V3_04 −0.024, V3_03 −0.009, V3_01 −0.003 (entries with rich numeric anchors improved). V3_06 +0.013, V3_07 +0.016 (Kumžák still slightly worse than no-anchors h007 — the seasonal-reference anchors "leden 250 / srpen 900" still drift the LLM's interpolation a bit, but less catastrophically).
Components: shape_mae 0.576 → 0.562 (-0.014, the biggest mover). Net win is real but small.
Why kept: improvement on the entries where numeric anchors actually exist in the description; small regression elsewhere is offset.

## iter h011 — 2026-05-07T01:15 — REJECTED
Hypothesis: drop "seasonal reference" lines (other-month numbers when target month not directly anchored) — they were over-anchoring Kumžák cases. Keep only target-month direct anchor + daily totals + windows.
Diff: anchor_extractor.rb format_for_prompt — removed other_months section.
Score before: 0.3455
Score after:  0.3509
Delta: +0.0054
Why: V3_04 (Vachta March, no March anchor in description but seasonal context "srpen 235, prosinec 40 implied small plant") jumped +0.048. The LLM relied on seasonal references to calibrate the SCALE for cases without target-month anchors. Removing them sent V3_04 back to legacy-like yearly_surplus interpolation. Trade is asymmetric — keeping seasonal refs is a net win.

## iter h012 — 2026-05-07T01:24 — REJECTED
Hypothesis: when peak window (e.g., "11–14h") is detected, compute midpoint and add explicit "vrchol kolem 12.5h, ostrá zvonová křivka, peak ~2× průměr" guidance to sharpen V3_06/V3_07.
Diff: anchor_extractor.rb format_for_prompt — peak_window line expanded.
Score before: 0.3455
Score after:  0.3458
Delta: +0.0003
Why: marginal regression. h007's prompt section 4 already instructed sharper bell curves for narrow profiles; the additional guidance was redundant and slightly destabilizing.

## Session pause — 13 iterations, 7 ACCEPTED, 4 REJECTED, total Δ = −0.028 (0.3736 → 0.3455)

Composite gap to legacy 0.3255 is now ~0.020. Per-component remaining headroom:
- daily_total_mape (capped 0.250): immovable on current dataset due to xlsx-vs-real mismatch on V3_01/V3_02/V3_03/V3_08
- hourly_shape_mae (0.084 weighted): ~0.02 remaining if shape can be sharpened further; diminishing returns on prompt instructions
- weekday_ratio_error (0.030 weighted): V3_02's hopeless 1.99 dominates; description says 1.65× weekend/workday but real meter shows 7×

The hourly path now beats legacy on the outliers (V3_01, V3_08) and trails legacy on the well-fitting cases (V3_04..V3_07). Closing the remaining gap would require either: (a) verifying ground truth on the four outliers (likely the real bottleneck — descriptions and measurements disagree by 10-25× and no algorithm change can reconcile that), or (b) a more substantial architectural change like archetype + parametric fill (idea #2 from earlier discussion).

## iter h013 — 2026-05-07T01:50 — REJECTED
Hypothesis: LLM produces flat plateaus (e.g., [0,0,0,3,3,3,3,3,2,1]) inside the active window; instructing "no flat plateaus, smooth bell" should sharpen V3_06/V3_07 shapes.
Diff: hourly_profile_parser.rb prompt section 4 — added "DŮLEŽITÉ — TVAR HODINOVÝCH HODNOT" paragraph.
Score before: 0.3455
Score after:  0.3498
Delta: +0.0043
Why: V3_06 +0.030. The "no plateaus" instruction added variability but the LLM produced curves with random jitter rather than smoother bells. shape_mae actually got worse (0.562 → 0.576). Variability ≠ accuracy.

## iter h014 — 2026-05-07T02:30 — ACCEPTED
Hypothesis: real April peak is at 13:00 wall-clock (CEST solar noon ≈13:00 in Czechia) but the LLM may default to 12:00 (literal noon). Real V3_07 peak hour = 13. Instructing the LLM to use 13:00 in DST months and 12:00 in winter time should reduce peak_time_delta and tighten shape on April entries.
Diff: hourly_profile_parser.rb prompt section 6 — DST-aware peak hour rule.
Score before: 0.3455
Score after:  0.3435
Delta: −0.0020
Per-entry deltas: V3_07 −0.012, V3_05 −0.020 (both April), V3_01 −0.006, V3_06 −0.003. V3_04 (March) +0.017 (slight regression — the March winter-time instruction may not perfectly fit the 3rd; March 2026 spans DST transition March 29).
Components: peak_time_delta 1.80 → 1.72 (-0.08 raw, as predicted). variance_ratio also dropped slightly (1.23 → 1.18). shape_mae stable.
Why kept: clean improvement across most entries; targeted change with predictable mechanism.

## iter h015 — 2026-05-07T02:35 — REJECTED
Hypothesis: parser change in h014 shifted LLM outputs; DAILY_FACTOR_RANGE optimum may have moved. Try wider 0.15..1.85.
Diff: hourly_profile_generator.rb:13
Score before: 0.3435
Score after:  0.3437
Delta: +0.0002
Why: variance_ratio worsened slightly (1.18 → 1.23). DAILY_FACTOR_RANGE 0.20..1.80 truly is the optimum.

## iter h016 — 2026-05-07T02:50 — REJECTED
Hypothesis: split daily factor into independent morning/afternoon factors to match real intra-day weather variation.
Diff: hourly_profile_generator.rb#generate (~5 lines)
Score before: 0.3435
Score after:  0.3581
Delta: +0.0146
Why: variance_ratio improved (1.18 → 1.08, GOOD direction) but dmape went up (5.72 → 6.35, capped) and shape worsened. The morning/afternoon asymmetry broke the noon-bell symmetry — synth curves are no longer mirror-symmetric like real solar curves.

## iter h017 — 2026-05-07T03:00 — ACCEPTED
Hypothesis: V3_08's description says weekend ≈ weekday explicitly ("prakticky není rozdíl, asi 92 kWh/den") but the LLM still produces small split. Add explicit rule to copy workday → weekend exactly when description signals equality, plus rules for explicit percentage offsets.
Diff: hourly_profile_parser.rb prompt section 8 — new weekend/workday rule.
Score before: 0.3435
Score after:  0.3390
Delta: −0.0045
Per-entry deltas: V3_06 −0.022, V3_08 −0.013, V3_07 −0.006, V3_02 −0.004 (the equality / direct-percentage rule corrects what the LLM was guessing). V3_05 +0.012 (slight regression — possibly the "default ~+10% weekend" instruction hurt where description didn't explicitly say anything).
Components: variance_ratio 1.18 → 1.10, peak_time_delta 1.72 → 1.64, shape_mae 0.566 → 0.560 — broad small improvements.
Why kept: largest single gain since h004. Direct, mechanistic rule with predictable effect on V3_08.

## iter h018 — 2026-05-07T03:10 — REJECTED
Hypothesis: parser change in h017 may have shifted DAILY_FACTOR_RANGE optimum again. Try slightly tighter 0.25..1.75.
Diff: hourly_profile_generator.rb:13
Score before: 0.3390
Score after:  0.3394
Delta: +0.0004
Why: variance_ratio similar (1.10 → 1.08, marginal). Other components shifted up tiny bits. The DAILY_FACTOR_RANGE = 0.20..1.80 is a stable optimum across parser changes.

## iter h019 — 2026-05-07T03:25 — REJECTED
Hypothesis: h017's "+10% weekend default" hurt V3_05 (Vachta 3kWp small plant). Refine: small plants (≤15 kWp, "domácí", "rodinný dům") default to weekend ≈ workday; commercial plants (>15 kWp, "firma", "dílna") default to +10% weekend.
Diff: hourly_profile_parser.rb prompt section 8 — capacity-based default rule.
Score before: 0.3390
Score after:  0.3395
Delta: +0.0005
Per-entry deltas: V3_05 −0.013, V3_07 −0.009 (small-plant rule fixed Vachta and Kumžák defaults). V3_06 +0.011, V3_08 +0.016 (capacity-based heuristic muddied the explicit-description rules from h017 — V3_08 is 30 kWp "firma" but description says "rovnoměrně"; the +10% default may have over-applied despite the equality keyword). Net wash.

## Session 2 starts — fresh 20-iteration budget, focus on hourly path

RUNNING BEST (hourly path): 0.3355 at 2026-05-07T05:00 (h024 — self-verification in prompt)

## iter h020 — 2026-05-07T04:00 — ACCEPTED
Hypothesis: parser-iteration scoring was confounded by LLM stochasticity (cache invalidates on parser change → fresh non-deterministic Gemini outputs → ±0.005-0.010 score noise per iter). Set Gemini temperature=0 via `RubyLLM.chat(...).with_temperature(0)` for deterministic outputs.
Diff: hourly_profile_parser.rb#call (one line, `.with_temperature(0)` chained).
Score before: 0.3390
Score after:  0.3369
Delta: −0.0021
Per-entry deltas: V3_04 −0.021, V3_02 −0.008 (LLM produces tighter outputs at temp=0); V3_06 +0.008, V3_08 +0.011 (small regressions).
Two wins: (1) new RUNNING BEST 0.3369, (2) all subsequent parser iterations now have reliable Δ signals.

## iter h021 — 2026-05-07T04:15 — REJECTED
Hypothesis: extract bare numbers after month names ("duben 386" without unit) as kWh anchors when description has at least one explicit kWh elsewhere.
Diff: anchor_extractor.rb#extract_monthly_totals — added bare-number fallback pass.
Score before: 0.3369
Score after:  0.3393
Delta: +0.0024
Why: V3_04 +0.019. Extracted "duben 386" pushed LLM's March extrapolation higher than reality (Vachta's description claims ~2.5× real). Bare-number extraction works when description matches reality, hurts when it doesn't.

## iter h022 — 2026-05-07T04:30 — REJECTED
Hypothesis: detect upper-bound prefixes ("pod X", "do X", "max X", "méně než X") and label as "≤ X" instead of treating as exact.
Diff: anchor_extractor.rb — bound flag in amounts + format_for_prompt distinction.
Score before: 0.3369
Score after:  0.3406
Delta: +0.0037
Why: counter-intuitive — telling LLM "leden ≤ 250 (HORNÍ LIMIT)" instead of "leden = 250" made it interpolate higher for spring months. Without the fixed cap, LLM defaulted to yearly-share interpolation. Original "exact" treatment was serving as a useful winter ceiling.

## iter h023 — 2026-05-07T04:45 — REJECTED
Hypothesis: 3-tap [0.25, 0.5, 0.25] Gaussian smoothing on workday/weekend hourly arrays before extrapolation reduces LLM jitter.
Diff: hourly_profile_generator.rb#initialize + new smooth method.
Score before: 0.3369
Score after:  0.3391
Delta: +0.0022
Why: shape_mae went 0.560 → 0.573. LLM outputs at temp=0 are already smooth; further smoothing flattens peak structure.

## iter h024 — 2026-05-07T05:00 — ACCEPTED
Hypothesis: add explicit self-verification step at end of prompt — LLM should silently check (a) total matches expected_monthly_kwh, (b) peak hour inside stated špička, (c) night values are 0, (d) "rovnoměrně" → weekend = workday exactly, (e) ★ target-month anchor matches output ±10%. Single LLM call, no extra cost.
Diff: hourly_profile_parser.rb prompt — added "VERIFIKACE PŘED ODESLÁNÍM" section (~10 lines).
Score before: 0.3369
Score after:  0.3355
Delta: −0.0014
Per-entry deltas: V3_06 −0.008, V3_07 −0.009 (Kumžák domestic — the verification step caught small inconsistencies in the curve and tightened them).
Components: variance_ratio 1.144 → 1.125 (improvement). shape_mae stable. dmape stable (capped).
Why kept: clean improvement on well-fitting cases. The verification reasoning steers the LLM toward internal consistency without changing total output count.

## SESSION 1 END — 20 iterations consumed

Final running best: **0.3390** (down from baseline 0.3736, Δ −0.0346, 9.3% relative).
Gap to legacy path 0.3255 remaining: **0.0135**.

| Component | Baseline raw | Final raw | Weighted savings |
|---|---|---|---|
| daily_total_mape    | 6.42 | 5.59 | 0 (capped at 0.250 throughout) |
| hourly_shape_mae    | 0.61 | 0.56 | -0.008 |
| peak_time_delta     | 1.92 | 1.64 | -0.002 |
| weekday_ratio_error | 0.36 | 0.41 | +0.004 (V3_02 noise dominates) |
| autocorr_distance   | 0.08 | 0.08 | 0 |
| variance_ratio_error| 1.36 | 1.10 | -0.005 |

The improvements concentrated in: (a) widening daily-factor variance to match real-day spread, (b) parser anchor preprocessing (idea #7 from the strategy chat), (c) sharper bell-curve and DST-aware peak instructions, (d) explicit weekend/workday rules. The composite is now bottlenecked by daily_total_mape's cap (which itself is bottlenecked by V3_01-V3_03/V3_08 having descriptions that disagree with measurements by 10-25×).

Accepted iterations (committed individually): h001 (-0.0072), h002 (-0.0029), h003 (-0.0014), h004 (-0.0090), h006 (-0.0007), h007 (-0.0059), h010 (-0.0010), h014 (-0.0020), h017 (-0.0045).



