# Autoresearch journal

RUNNING BEST: 0.2083 at 2026-04-11 (iter S3.3: prompt tuning — smooth profiles + no-all-zero rule)

## iter 000 — 2026-04-10T22:00 — BASELINE

No change. Just establishing the baseline score.

```
Scored: 49/50  (failed: 1, P033 bad data)
Overall composite: 0.2793
  production (34): 0.3201
  consumption (15): 0.1868

Component averages:
  daily_total_mape       raw=0.5392  weighted=0.0899
  hourly_shape_mae       raw=0.6909  weighted=0.1036
  peak_time_delta        raw=5.5102  weighted=0.0459
  weekday_ratio_error    raw=0.1166  weighted=0.0087
  autocorr_distance      raw=0.0907  weighted=0.0045
  variance_ratio_error   raw=1.4124  weighted=0.0282
```

Biggest contributors: hourly_shape_mae and daily_total_mape. Focus there.

## iter 001 — 2026-04-10T22:15 — ACCEPTED

Hypothesis: daily factor range `0.7 + rand*0.6` (0.7..1.3) is too narrow; real solar has much wider day-to-day variance (cloudy vs clear). Widening to `0.5 + rand*1.0` (0.5..1.5) should reduce `variance_ratio_error` and `daily_total_mape`.

Diff: `lib/lupina/edc_generator.rb:97-102`

```
-    hash[date] = 0.7 + @rng.rand * 0.6
+    hash[date] = 0.5 + @rng.rand * 1.0
```

Score before: 0.2793
Score after:  0.2697
Delta: **-0.0096**

Component changes:
| component            | before | after  | Δ       |
|----------------------|--------|--------|---------|
| daily_total_mape     | 0.5392 | 0.5045 | -0.0347 |
| hourly_shape_mae     | 0.6909 | 0.6909 |  0      |
| peak_time_delta      | 5.51   | 5.47   | -0.04   |
| weekday_ratio_error  | 0.1166 | 0.1162 | ~0      |
| autocorr_distance    | 0.0907 | 0.0909 | ~0      |
| variance_ratio_error | 1.4124 | 1.2444 | -0.168  |

Kept. Production slice improved (0.3201 → 0.3062); consumption unchanged (0.1868). Variance-ratio-error dropped ~12%, confirming the hypothesis.

## iter 002 — 2026-04-10T22:20 — ACCEPTED

Hypothesis: iter 1 confirmed wider daily factors help. Push further to `0.3 + rand*1.4` (0.3..1.7, max:min ratio 5.7:1). Real cloudy-to-clear daily ratios are typically 10:1 so still conservative.

Diff: `lib/lupina/edc_generator.rb:100`

```
-    hash[date] = 0.5 + @rng.rand * 1.0
+    hash[date] = 0.3 + @rng.rand * 1.4
```

Score before: 0.2697
Score after:  0.2631
Delta: **-0.0066**

Component changes (vs iter 1):
| component            | before | after  | Δ       |
|----------------------|--------|--------|---------|
| daily_total_mape     | 0.5045 | 0.4783 | -0.0262 |
| hourly_shape_mae     | 0.6909 | 0.6910 |  0      |
| peak_time_delta      | 5.47   | 5.46   | -0.01   |
| weekday_ratio_error  | 0.1162 | 0.1161 | ~0      |
| autocorr_distance    | 0.0909 | 0.0913 | +0.0004 |
| variance_ratio_error | 1.2444 | 1.1406 | -0.104  |

Kept. Production slice 0.3062 → 0.2967; consumption unchanged. Diminishing returns vs iter 1 (-0.0096 → -0.0066), suggests we're approaching the right range.

## iter 003-008 — 2026-04-10T22:25 — sweep of solar envelope exponent

Hypothesis: real solar curves are sharper than pure `sin(phase)` due to atmospheric airmass + inverter clipping. Try `sin(phase) ** n` for various n, keep the best.

Diff: `lib/lupina/edc_generator.rb:109`

| iter | n   | composite | hourly_shape_mae | delta   | verdict  |
|------|-----|-----------|------------------|---------|----------|
| 003  | 1.2 | 0.2607    | 0.6745           | -0.0024 | ACCEPTED |
| 004  | 1.4 | 0.2579    | 0.6602           | -0.0028 | ACCEPTED |
| 005  | 1.6 | 0.2558    | 0.6476           | -0.0021 | ACCEPTED |
| 006  | 2.0 | 0.2524    | 0.6277           | -0.0034 | ACCEPTED |
| 007  | 2.5 | 0.2502    | 0.6129           | -0.0022 | ACCEPTED |
| 008  | 3.0 | 0.2493    | 0.6080           | -0.0009 | ACCEPTED |
| 009  | 4.0 | 0.2503    | 0.6142           | +0.0010 | REJECTED |

Best: **n = 3.0**. sin^3.0 is the optimum before we overshoot. Shape_mae dropped 0.691 → 0.608 across the sweep, the biggest single component improvement this session.

## iter 010 — 2026-04-10T22:32 — REJECTED (noise tuning)

Hypothesis: `0.85 + rand*0.30` (±15% per-interval noise) is too noisy; real meters show less jitter. Try `0.95 + rand*0.10` (±5%).

Score before: 0.2493
Score after:  0.2494
Delta: **+0.0001** (wash)

Production slice improved (0.2893 → 0.277) and peak_time_delta dropped (5.47 → 5.28), but autocorr_distance regressed (0.091 → 0.102) because synth now too smooth compared to real. Net wash. Reverted.

## iter 011 — 2026-04-10T22:34 — REJECTED (fine-grained sin exponent)

Tried `sin(phase) ** 2.8` to check if 3.0 was slightly over. Score went 0.2493 → 0.2496. Confirms 3.0 as local optimum. Reverted.

## iter 012-014 — 2026-04-10T22:36 — daily factor re-sweep after sin^3.0

Interaction effect: after sin^3.0 changed the shape, the optimal daily factor range may have shifted. Re-sweep.

| iter | range     | composite | delta   | verdict  |
|------|-----------|-----------|---------|----------|
| 012  | 0.2..1.8  | 0.2476    | -0.0017 | ACCEPTED |
| 013  | 0.1..1.9  | 0.2469    | -0.0007 | ACCEPTED |
| 014  | 0.0..2.0  | 0.2470    | +0.0001 | REJECTED |

Best: **0.1 + rand*1.8** (range 0.1..1.9, max:min ratio 19:1). Note that the optimal range widened after iter 2 (was 0.3..1.7) once the solar envelope was sharper — sharper envelope tolerates wider daily variance.

## Session summary (2026-04-10T22:00 → 22:40)

14 iterations. **Composite 0.2793 → 0.2469. Δ = -0.0324 (-11.6%).**

Two changes accepted, both in `lib/lupina/edc_generator.rb`:

```diff
- hash[date] = 0.7 + @rng.rand * 0.6
+ hash[date] = 0.1 + @rng.rand * 1.8
```

```diff
- Math.sin(phase)
+ Math.sin(phase) ** 3.0
```

Component improvements:

| component            | baseline | final  | Δ       |
|----------------------|----------|--------|---------|
| daily_total_mape     | 0.5392   | 0.4677 | -0.0715 |
| hourly_shape_mae     | 0.6909   | 0.6079 | -0.0830 |
| peak_time_delta      | 5.51     | 5.30   | -0.21   |
| weekday_ratio_error  | 0.1166   | 0.1110 | -0.006  |
| autocorr_distance    | 0.0907   | 0.0965 | +0.006  |
| variance_ratio_error | 1.4124   | 1.0964 | -0.316  |

Biggest wins: variance_ratio_error (-22%), hourly_shape_mae (-12%), daily_total_mape (-13%). Only regression: autocorr_distance (+6%, tiny absolute) — the wider daily factors introduce more day-to-day jumps that mildly reduce lag-1 correlation.

**What's still hard:**
- `hourly_shape_mae` 0.608 — dominant remaining component. Stuck at sin^3.0 local optimum. Future work: asymmetric envelope (morning/afternoon differ), or per-month tuning of the exponent.
- `peak_time_delta` 5.30 — dominated by low-signal entries (P024, P016, P020, P028 with near-zero export). The metric is noise on these entries. Either filter by signal or use a different peak metric.
- `daily_total_mape` 0.468 — further wins would need better weather simulation (log-normal? AR(1)?).

**What to try next:**
1. Auto-regressive daily factors (clouds correlate day-to-day).
2. Asymmetric solar envelope (morning sharper than afternoon).
3. Filter out low-signal entries from peak_time_delta.
4. Try log-normal distribution for daily factors instead of uniform.

# Session 2 — hourly_shape_mae focus

Running best after session 1: 0.2469. Remaining dominant component: `hourly_shape_mae` at 0.6079 (weighted 0.091).

## iter 015-017 — per-month envelope exponent

Hypothesis: optimal solar exponent may differ by month (winter short days vs summer inverter clipping).

| iter | winter / summer | composite | shape_mae | verdict  |
|------|-----------------|-----------|-----------|----------|
| 015  | 2.5 / 3.5       | 0.2470    | 0.6086    | REJECTED |
| 016  | 3.5 / 2.5       | 0.2474    | 0.6114    | REJECTED |

Neither direction helps. The envelope exponent is not month-dependent in a simple way.

## iter 018 — ACCEPTED (asymmetric envelope)

Hypothesis: real solar shape may be asymmetric — different behavior before vs after solar noon.

Diff: split exponent at phase=π/2.

```
-      Math.sin(phase) ** 3.0
+      exponent = phase < Math::PI / 2 ? 3.5 : 2.5
+      Math.sin(phase) ** exponent
```

Score: 0.2469 → **0.2464** (-0.0005). shape_mae: 0.6079 → 0.6047.

Morning (phase < π/2) gets sharper exponent (less value far from peak); afternoon gets flatter exponent (more value far from peak). Empirically: real data shows morning ramp is *slower* than symmetric sin would suggest (atmospheric depth + panel warmup), while afternoon decay *extends* further (warm panels + continuing until sunset).

Small absolute improvement but confirms an asymmetry signal exists.

## iter 019-022 — tune the asymmetry further

| iter | morning/afternoon | composite | verdict  |
|------|-------------------|-----------|----------|
| 019  | 4.0 / 2.0         | 0.2470    | REJECTED |
| 020  | 3.5/2.5 + peak shift +0.3h | 0.2466 | REJECTED (tied) |
| 021  | 4.0 / 3.0         | 0.2465    | REJECTED (tied) |
| 022  | 4.5 / 2.5         | 0.2465    | REJECTED (tied) |

3.5/2.5 is the local optimum. Pushing further in any direction is a wash or regression.

## iter 023 — REJECTED (AR(1) daily factors)

Hypothesis: real weather has day-to-day persistence (cloudy stretches, clear weeks). Replace iid uniform daily factors with AR(1): `f[n] = 0.5·f[n-1] + 0.5·uniform(0.1, 1.9)`.

Score: 0.2464 → **0.2557** (+0.0093). daily_total_mape regressed from 0.4677 to 0.5045.

Why: AR(1) compresses variance (the smoothing reduces extreme values). Score rewards wider variance (matches real cloudy-clear distribution), so smoothing backfires. Reverted.

## iter 024 — REJECTED (Normal daily factors)

Hypothesis: real daily-total distribution may be bell-shaped. Replace uniform with Normal(μ=1, σ=0.5) clamped to [0.1, 1.9].

Score: 0.2464 → 0.2491 (+0.0027). daily_total_mape 0.4677 → 0.4747.

Why: real distribution has heavier tails than Normal — the flat uniform is closer to truth than bell-shaped. Reverted.

## Diagnostic: where is shape_mae coming from?

Dumped real vs synth normalized workday shapes for 3 entries:

| entry | description                                    | real peak   | synth peak  | L1    | cause                                    |
|-------|------------------------------------------------|-------------|-------------|-------|------------------------------------------|
| P014  | "čistě výrobní, nikdo nespotřebovává"         | h13 (16.5%) | h13 (16.7%) | 0.092 | near-ideal                               |
| P029  | "jede od 9 do 16"                             | bimodal: h12 (19%), h14 (18%) | smooth h12 (17%) | 0.389 | LLM profile too coarse (uniform 0.4 during 9-15) — real has lunch-break dip |
| P034  | "přes týden vše sežereme"                     | h12-13 solar peak | all zero    | 1.000 | LLM profile all-zero, real has significant workday export — annotation bug |

Plus distribution across all 49 entries:
- shape_mae < 0.1: **1 entry** (P014) — generator near-perfect
- 0.1-0.3: 6 entries — good
- 0.3-0.5: 8 entries — moderate
- 0.5-0.8: 26 entries — dominant
- 0.8-1.1: 6 entries
- 1.1+: 2 entries (P016 shape=1.82, P020 shape=1.98) — catastrophic, annotation bugs

P016 ("březen skoro nic nedá") has 116 kWh total for 34 kWp, flat at ~0.04 kWh/hour — broken meter or near-zero signal. P020 real has proper workday solar curve, but description says "přes týden vše sežereme" — annotator got it wrong.

**Conclusion:** shape_mae has a soft ceiling bounded by annotation quality. ~15% of entries have descriptions that contradict their data. The generator can only match what the (description → LLM profile) pipeline produces. Further shape_mae improvements require either fixing annotations or changing the description_parser (off-limits per program.md).

## Session 2 summary

10 iterations. **Composite 0.2469 → 0.2464. Δ = -0.0005 (-0.2%).**

One accepted change (asymmetric envelope 3.5/2.5), all others rejected. Diminishing returns confirmed.

**Cumulative (sessions 1 + 2):** 24 iterations, composite 0.2793 → 0.2464, **-11.8%**.

Final generator state:

```ruby
# Daily factor distribution
hash[date] = 0.1 + @rng.rand * 1.8

# Asymmetric solar envelope
phase = (hour - solar[:rise]) / (solar[:set] - solar[:rise]) * Math::PI
exponent = phase < Math::PI / 2 ? 3.5 : 2.5
Math.sin(phase) ** exponent
```

**What autoresearch cannot fix (without rewriting the rules):**
- Annotation errors in eval data (~15% of entries have description/data mismatch)
- LLM profile granularity (hour-level, can't capture lunch-break dips at 15-min resolution)
- Low-signal entries (P016, P024) where the metric measures noise

# Session 3 — description_parser.rb unlocked

User asked to lift the ban on editing `description_parser.rb` and let autoresearch tune the LLM prompt itself. Program.md updated, cache keyed by parser-file hash so prompt changes auto-invalidate the cache.

**New baseline under versioned cache:** 0.2478 (vs. 0.2464 under old cache — LLM is non-deterministic, re-parsing gave slightly different profiles).

## iter S3.1 — ACCEPTED (smooth values + softer ratio rules)

Hypothesis: the LLM produces binary 0/1 profiles because the prompt explicitly says "Stačí 1.0 pro hodiny kdy přetoky ano, 0 kdy ne". Real profiles are smooth. Also the "<0.3 ratio → narrow peaks only" rule forces all-zero workday profiles for heavy-consumption cases, which don't match real data.

Edits: removed the binary-is-fine line, softened ratio-based guidance to map to 0.1-0.4 values instead of 0, added explicit instruction that "vše sežereme" ≠ 0 if ratio > 0.1.

Score: 0.2478 → 0.2410 (-0.0068).

| component            | before | after  | Δ      |
|----------------------|--------|--------|--------|
| daily_total_mape     | 0.4363 | 0.7714 | +0.335 |
| hourly_shape_mae     | 0.6239 | 0.4816 | **-0.142** |
| peak_time_delta      | 5.15   | 2.76   | **-2.39** |
| weekday_ratio_error  | 0.265  | 42.4   | pegged cap |
| variance_ratio_error | 0.946  | 0.967  | +0.021 |

**shape_mae -23%** and **peak_time_delta -46%** are huge wins. daily_total_mape and weekday_ratio_error regressed because some entries got non-zero workdays that the real data doesn't have (weekday_ratio_error now capped at the normalizer). Net composite improved because the shape wins dominate.

## iter S3.2 — ACCEPTED (concrete smooth-profile examples)

Hypothesis: add three explicit examples showing smooth profiles (0.2-0.5 values) for common scenarios ("vše sežereme", factory 15:00, two-shift 6-22). The LLM learns better from examples than from abstract rules.

Edits: replaced binary FULL/ZERO examples with smooth ones. Added "vše sežereme" example with 0.2 workday values.

Score: 0.2410 → **0.2213** (-0.0197).

| component            | before | after  | Δ      |
|----------------------|--------|--------|--------|
| daily_total_mape     | 0.7714 | 0.5755 | -0.196 |
| hourly_shape_mae     | 0.4816 | 0.4917 | +0.010 |
| variance_ratio_error | 0.967  | 0.870  | -0.097 |

Biggest single-iteration improvement in the whole run. Concrete examples work.

## iter S3.3 — ACCEPTED (no-all-zero rule)

Hypothesis: the wre=42 pathology comes from a handful of entries where the LLM still produces all-zero workday profiles despite iter S3.2's examples. Add an explicit rule: if ratio > 0.05, workday profile must have minimum 0.1 during solar hours.

Score: 0.2213 → **0.2083** (-0.0130).

| component            | before | after  | Δ      |
|----------------------|--------|--------|--------|
| daily_total_mape     | 0.5755 | 0.3039 | **-0.272** |
| hourly_shape_mae     | 0.4917 | 0.4847 | -0.007 |
| peak_time_delta      | 2.79   | 2.66   | -0.13  |
| weekday_ratio_error  | 42.2   | 42.2   | unchanged (pegged) |
| variance_ratio_error | 0.870  | 0.776  | -0.094 |

daily_total_mape dropped -47%, the biggest component improvement. The hard rule on minimum values prevents LLM from zeroing out entire days.

## iter S3.4 — REJECTED (too-permissive "vše sežereme" exception)

Hypothesis: some entries (P031, P035, P028) have real data with **actually zero workday export** — the "vše sežereme" description is literally accurate. Allow the LLM to produce zero workdays when ratio < 0.15 and description uses "vše sežereme".

Score: 0.2083 → 0.2230 (+0.0147). Reverted.

Diagnostic dump showed that for P031: real workday total = 1.7 kWh, weekend total = 1013 kWh. For P035: 3.9 vs 4566. These entries legitimately have all export on weekends. My exception was correct for these, but the LLM applied it too broadly, zeroing workdays on entries where real data had non-zero values. Net loss on shape_mae and daily_total_mape outweighed the wre fix.

Conclusion: the zero-vs-non-zero decision can't be made from description alone. Keep the strict rule — it hurts a few true-zero entries but helps the majority. The wre component is capped at 0.15 contribution anyway.

## iter S3.5 — REJECTED (bimodal + east-facing examples)

Hypothesis: adding examples for lunch-break bimodal and east-facing asymmetric patterns might help a few entries (P029 lunch dip, C007 polední pauza).

Score: 0.2083 → 0.2146 (+0.0063). Reverted.

The LLM seems to over-apply these new patterns to entries where they don't fit. More examples ≠ better; the existing set is already at the right specificity.

## Session 3 summary

5 iterations, 3 ACCEPTED (S3.1, S3.2, S3.3), 2 REJECTED (S3.4, S3.5). **Composite 0.2478 → 0.2083. Δ = -0.0395 (-16%).**

**Cumulative (sessions 1+2+3):** 29 iterations, composite **0.2793 → 0.2083 (-25.4%)**.

Key component trajectory:

| component            | baseline | end S1 | end S2 | end S3 | Δ from baseline |
|----------------------|----------|--------|--------|--------|-----------------|
| daily_total_mape     | 0.5392   | 0.4677 | 0.4677 | 0.3039 | **-44%**        |
| hourly_shape_mae     | 0.6909   | 0.6080 | 0.6047 | 0.4847 | **-30%**        |
| peak_time_delta      | 5.51     | 5.30   | 5.31   | 2.66   | **-52%**        |
| weekday_ratio_error  | 0.117    | 0.111  | 0.111  | 42.2   | pegged cap      |
| autocorr_distance    | 0.091    | 0.097  | 0.096  | 0.094  | ~0              |
| variance_ratio_error | 1.41     | 1.10   | 1.10   | 0.776  | **-45%**        |

Session 3 unlocked the biggest single wins: shape_mae finally moved (had been stuck at 0.608 through sessions 1-2 because it depends on LLM profile quality). Concrete examples in the prompt turned out to be more effective than abstract rules.

**Next exploration directions:**
- Dig into which consumption profiles are worst (consumption only -5% vs production -19%)
- Further examples in the prompt targeted at specific failure modes (after examining top-worst cases)
- Consider a smarter wre metric in the scorer that doesn't blow up on ratio outliers





