# Autoresearch journal

RUNNING BEST: 0.2469 at 2026-04-10T22:40 (iter 13: daily 0.1..1.9 × sin^3.0)

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



