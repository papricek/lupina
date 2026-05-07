# Autoresearch program — Lupina generator tuning (V3 dataset)

You are an autonomous research agent tuning the Lupina EDC generator. Your job: lower the composite score reported by `eval/bin/score` by modifying the generator's code and re-measuring. Work in a loop until no more improvements can be found, the iteration cap is hit, or 5 consecutive rejections.

## Current state (multi-track)

| Path | Dataset | Composite | Notes |
|---|---|---|---|
| `legacy` | V3 (production) | **0.3255** | Reference baseline; do not actively tune |
| `hourly` | V3 (production) | **0.3160** | Tuned over 38 iterations (h001-h035). Beats legacy by 0.0095. 5/8 entries win. |
| `hourly_consumption` | CV1 (consumption) | **0.1710** | Initial baseline. No iterations yet — open for autoresearch. |

The two active paths are independent — production iterations and consumption iterations don't interact. Pick one per session.

## The score

```bash
cd /Users/patrikjira/Work/wattlink

# Production V3 hourly path (8 entries × 4 tiers = 32 cases)
LUPINA_PATH=hourly chruby-exec ruby-3.2.2 -- bin/rails runner /Users/patrikjira/Work/claude/lupina/eval/bin/score

# Consumption CV1 path (40 entries × 2 tiers = 80 cases)
LUPINA_PATH=hourly_consumption chruby-exec ruby-3.2.2 -- bin/rails runner /Users/patrikjira/Work/claude/lupina/eval/bin/score

# Legacy production baseline (default if no env var)
LUPINA_PATH=legacy chruby-exec ruby-3.2.2 -- bin/rails runner /Users/patrikjira/Work/claude/lupina/eval/bin/score
```

Caches/reports per path:
- `hourly` → `eval/parse_cache_hourly/`, `eval/score_hourly.json`
- `hourly_consumption` → `eval/parse_cache_consumption/`, `eval/score_consumption.json`
- `legacy` → `eval/parse_cache/`, `eval/score.json`

## ⚙ Resume checklist (read first when starting a new session)

1. **Confirm git state**:
   ```bash
   git -C /Users/patrikjira/Work/claude/lupina status              # should be clean
   git -C /Users/patrikjira/Work/claude/lupina log --oneline -5     # see most recent accepted iterations
   tail -20 /Users/patrikjira/Work/claude/lupina/eval/journal.md    # see RUNNING BEST and recent attempts
   ```

2. **Set up bundler local override** (so wattlink loads lupina from disk, not GitHub) — required for fast parser iteration:
   ```bash
   cd /Users/patrikjira/Work/wattlink
   chruby-exec ruby-3.2.2 -- bundle config --local local.lupina /Users/patrikjira/Work/claude/lupina
   chruby-exec ruby-3.2.2 -- bundle install
   chruby-exec ruby-3.2.2 -- bundle info lupina | head -5    # Path: should be /Users/patrikjira/Work/claude/lupina
   ```

3. **Confirm baseline** matches journal:
   ```bash
   LUPINA_PATH=hourly chruby-exec ruby-3.2.2 -- bin/rails runner /Users/patrikjira/Work/claude/lupina/eval/bin/score | grep "Overall composite"
   # Should show 0.316 (or whatever the current RUNNING BEST line says)
   ```

4. **At session end**, after pushing accepted iterations to GitHub:
   ```bash
   git -C /Users/patrikjira/Work/claude/lupina push origin main
   cd /Users/patrikjira/Work/wattlink
   chruby-exec ruby-3.2.2 -- bundle config unset local.lupina    # if you want wattlink to fetch from GitHub
   chruby-exec ruby-3.2.2 -- bundle install
   git add Gemfile.lock && git commit -m "Bump lupina to <new-sha>"
   ```

## Dataset shape

- 8 EAN-month pairs × 4 description tiers = **32 cases per iteration**
- Tiers: `popis` (technical short), `popis_2` (technical medium), `popis_laik` (layman), `popis_zkuseny` (expert with numbers)
- Real CSVs from wattlink `edc_readings`, March/April 2026
- xlsx "Přetoky (MWh)" column = yearly export, fed directly to lupina (capped at capacity_kwp × 999)
- ⚠ Several entries (V3_01, V3_02, V3_03, V3_08) have ~10-25× xlsx-vs-measured discrepancy on yearly export. **`daily_total_mape` is dataset-noise-bound at 0.250 weighted on the cap; do not chase it directly.**

## Two parallel paths

The harness scores either of two architectures via `LUPINA_PATH` env var:

- **`legacy`** (baseline 0.3255): description → relative weekday profile (`DescriptionParser`) → × solar envelope × renormalize to monthly slice of `yearly_surplus_kwh`. Strong solar prior, brittle to xlsx-yearly mismatch.
- **`hourly`** (current best 0.3160): description → LLM produces 24 absolute kWh-per-hour values for typical workday/weekend/holiday (`HourlyProfileParser`) → script upsamples to 15-min with multiplicative noise + per-day weather factor (`HourlyProfileGenerator`). LLM does the heavy reasoning; script just extrapolates. Anchor preprocessing in `AnchorExtractor`.

Caches and reports are isolated per path:
- `eval/parse_cache/` and `eval/score.json` — legacy
- `eval/parse_cache_hourly/` and `eval/score_hourly.json` — hourly

## What you may edit

**Hourly (production V3):**
- `lib/lupina/hourly_profile_parser.rb` — LLM prompt + post-processing for přetoky
- `lib/lupina/hourly_profile_generator.rb` — extrapolation knobs (`QUARTER_NOISE_RANGE`, `DAILY_FACTOR_RANGE`, `INTRA_HOUR_SHAPE`). **Shared with consumption path.**
- `lib/lupina/anchor_extractor.rb` — Czech regex extraction for přetoky anchors

**Hourly_consumption (CV1):**
- `lib/lupina/hourly_consumption_parser.rb` — LLM prompt for spotřeba (sector-aware shape priors, baseline emphasis, no `capacity_kwp`)
- `lib/lupina/consumption_anchor_extractor.rb` — Czech regex extraction for spotřeba (sector keywords, baseline kW, peak hour, active window)

New helper files under `lib/lupina/` are allowed.

Legacy path files (`edc_generator.rb`, `solar_model.rb`, `day_resolver.rb`, `description_parser.rb`) — only touch if revisiting the legacy path.

## What you must NOT edit

- `lib/lupina.rb` — public API. Adding NEW methods is allowed; modifying existing ones is not.
- `lib/lupina/configuration.rb`, `extractor.rb`, `version.rb`
- `eval/**` — harness and data are ground truth
- `.gemspec`, `Gemfile*`, `sig/**`

## The loop

For each iteration:

1. Read the last 3 journal entries from `eval/journal.md` to see what's been tried.
2. Form ONE hypothesis. Be specific: which component is the target, which file, which lines, which direction. Look at per-tier and per-entry breakdown to identify weakness.
3. Run `eval/bin/verify` — if it fails, fix first.
4. Make the edit. Keep changes small and isolated (≤20 lines diff).
5. Run `eval/bin/verify` — if it fails, revert (`git checkout -- <file>`) and try a different hypothesis.
6. Run `eval/bin/score`. Compare composite to running best.
7. **If score improved**:
   - Keep the change.
   - Update RUNNING BEST in `eval/journal.md`.
   - Append journal entry with `ACCEPTED`.
   - `git commit` the lupina source change + journal update. Each accepted iteration becomes its own commit.
8. **If score regressed**:
   - Revert (`git checkout -- <file>`).
   - Append journal entry with `REJECTED` and a one-sentence "Why".
   - Do NOT commit on rejection.
9. Go to step 1.

### Commit format

```bash
git -C /Users/patrikjira/Work/claude/lupina add lib/lupina/<file>.rb eval/journal.md
git -C /Users/patrikjira/Work/claude/lupina commit -m "iter hNNN: <short> (-0.0XXX)"
```

Stage only edited lupina source + `eval/journal.md`. Do NOT stage `eval/score*.json` or anything under `eval/dataset/` / `eval/parse_cache*/` (gitignored).

## Tested ideas (don't repeat)

These have been tried and rejected — don't waste iteration budget re-testing without a strong reason:

| Idea | Iter | Result |
|---|---|---|
| AR(1) correlated daily factors | h005 | +0.010 — adjacent-day correlation reduces variance below real |
| Constant daily factor (var=0) | h003 | +0.067 — synth_var << real_var |
| `DAILY_FACTOR_RANGE` narrowing past 0.20-1.80 | h008/h015/h018/h031 | All marginal regressions; 0.20-1.80 is stable optimum |
| Soften solar envelope morning 3.5→3.0 | h002 | small regression |
| Drop seasonal-reference anchors | h011 | hurts cases without target-month anchor |
| Bare-number anchor extraction (e.g. "duben 386") | h021 | overfits when description claims diverge from reality |
| Upper-bound flag for "pod X" | h022 | counter-intuitive — fixed cap was useful winter ceiling |
| 3-tap Gaussian smoothing on hourly arrays | h023 | flattens peaks, shape_mae worse |
| AM/PM split daily factor | h016 | breaks noon-bell symmetry |
| Concrete real-data example in prompt | h026 | overfits to one entry, hurts similar ones |
| "No flat plateaus" instruction | h013 | adds jitter, not bell shape |
| Lower `solar_peak_fraction` 0.75→0.55 | h034 | over-compresses curves |
| Extend anchor discount to all categories (not just target) | h033 | cumulative discounts compound, V3_04 +0.031 |
| Tighten target-month discount past 0.80 (try 0.75) | h036 | over-discounts reasonable claims |
| Cross-check rule (anchor vs yearly×share) | h037 | pushes good anchors to yearly-based, hurts cases where anchor was right |

## Accepted ideas (current state baked in)

These are *in* the codebase. Reading the file diffs around them tells you the current rules:

| Iter | What | Δ |
|---|---|---|
| h001-h003, h006 | Widen `DAILY_FACTOR_RANGE` to 0.20-1.80 | -0.012 cumulative |
| h004 | Anchor priority in parser prompt | -0.009 |
| h007 | Sharper bell curves for narrow domestic profiles | -0.006 |
| h010 | `AnchorExtractor` with calibration framing | -0.001 |
| h014 | DST-aware peak hour (13 in summer, 12 in winter) | -0.002 |
| h017 | Explicit weekend/workday equality + percentage rules | -0.005 |
| h020 | Gemini `temperature=0` for deterministic LLM | -0.002 |
| h024 | Self-verification step at end of prompt | -0.001 |
| h025 | Softer bell, peak ~1.5-2× avg with afternoon trail | -0.001 |
| h027 | Anchor decision tree + capacity discount for unanchored | -0.006 |
| h030 | Capacity-tiered discount (≤15 kWp → 0.65-0.80×) | -0.004 |
| h032 | Universal 0.85× discount on target-month anchors | -0.005 |
| h035 | Tighten target-month discount to 0.75-0.85 (median 0.80) | -0.004 |

## Promising ideas not yet tried — production hourly path

Order roughly by expected value × ease:

1. **True two-pass self-critique** — first call returns draft, second call reviews against anchors and revises. ~10 min iteration (2× LLM cost). The single-pass verification (h024) gave a small win; two-pass might give more.
2. **Schema-locked Gemini output** — use Gemini's structured-output / `response_format` if RubyLLM exposes it. Removes JSON parse failures, constrains numeric ranges. Cheap to wire.
3. **Multi-sample ensemble** — call LLM 3× per (entry, tier), average the resulting hourly arrays. Expensive (3× cost) but smooths residual non-determinism. Only worth it if iteration budget is large.
4. **Phase D: structured spec architecture** — LLM emits `{peak_hour, peak_kwh, monthly_total, active_window, peak_sharpness}` (~6 floats). Ruby script generates the curve from spec via Beta distribution. Tighter LLM output space, fewer hallucinations. Big refactor (~150 LOC); high ceiling but high risk.
5. **Per-tier prompt customization** — popis_zkuseny (numerical) is currently the worst-performing tier (~0.337) vs popis_laik (~0.322). Different LLM strategy per tier?
6. **Capacity-conditional `DAILY_FACTOR_RANGE`** — small plants have stable daily totals (low real variance), large plants have weather-driven swings. Pass capacity through and use narrower range for ≤15 kWp.
7. **Refine `AnchorExtractor`** — extract peak intensity claims ("kolem 6 kWh/h"), specific weekend/workday percentages ("o 25 %"), holiday treatment.
8. **Different LLM model** — try Gemini Pro vs Flash, or Claude. RubyLLM supports model swap.

## Promising ideas — consumption hourly_consumption path

CV1 baseline 0.1710 is already much better than V3 production's first baseline. Don't apply production's "customer overestimation" discount blindly — descriptions for CV1 were generated FROM real measurements, so the bias direction is different. Track LAIK quality (real users will write LAIK-style).

Order by expected value × ease:

1. **Narrower DAILY_FACTOR_RANGE for consumption** — variance_ratio raw is 1.70, suggesting synth daily-total spread is too wide vs stable consumption days. Real consumers (especially industrial 24/7) have very tight daily totals. Try `0.85..1.15` (var=0.0075) for consumption path. The shared generator currently uses production's `0.20..1.80` which is way too wide for consumption. Likely big win.
2. **Sector-specific peak hour rules** — peak_time_delta raw 3.6 is the most movable component. CV1_17/18 (Frýdek-Místek) have biggest delta. Add explicit rules: residential evening peak (18-19h), office midday (11-13h), industrial 24/7 (no peak), restaurant evening (19-21h), school morning (10-11h).
3. **Bimodal residential check** — verify residential entries get TWO peaks (morning + evening), not one. Add validation in parser post-processing if missing.
4. **Heating-aware seasonality calibration** — March (heating still on) vs April (transition) should differ noticeably for heating-dominant accounts. The current `MONTHLY_SHARE` table is generic; tighten for accounts where description mentions "topení" / "v zimě".
5. **Baseline parsing strength** — `consumption_anchor_extractor` extracts `baseline_kw` when phrased explicitly. Cover more synonyms ("nepřetržitý odběr", "stand-by", "ledničky", "stálá zátěž").
6. **Per-EAN reasoning trace inspection** — read the cache's `reasoning` field for CV1_17/18 and CV1_11/12 to understand WHY they're worst. Targeted fixes from there.
7. **Two-pass self-critique** (same idea as production) — single-pass verification helped V3 (-0.001). Two-pass might give more on consumption where the LLM has more freedom (no solar prior to fall back on).
8. **Sector classifier as separate first call** — small first LLM call returns just sector category, second call uses sector-specific prompt template.

## Known issues / lessons

- **Gemini API hangs occasionally**. If a score run goes >12 min with <10s CPU, kill the process and re-run. Cache from the partial run is saved per-completed-call. ([detailed example below])
- **Temp=0 isn't fully deterministic** but reduces noise enough for cleanly distinguishing signal from noise on parser changes.
- **Tier-balanced score** matters: don't optimize for popis_zkuseny alone (overfits to numerical descriptions).
- **Customer overestimation is real** and systematic (~20-30%). The 0.80× anchor discount in current prompt addresses this.
- **V3_03 and V3_04 are dataset-noise dominated**. Descriptions claim 2-25× the measured monthly export. Don't chase these — they cap composite around 0.32.

## Rules

- ONE change per iteration. Don't combine hypotheses.
- Changes must be small and isolated — if the diff is over 20 lines, split it.
- Never edit tests, data, or the scorer itself.
- **Commit every ACCEPTED iteration.** No commit on REJECTED.
- Never `git push` from inside the loop. Push at session end (manually) so wattlink can `bundle update lupina`.
- If you make 5 consecutive REJECTED iterations, pause and ask for direction.
- Stop after 20 iterations total per run.

## Determinism

The scorer uses `seed: 42` for all generator calls. With Gemini `temperature=0`, scoring is approximately deterministic given the code state. Re-running the same code gives the same composite within ±0.001 of noise.

## Cache

- Hourly path: `eval/parse_cache_hourly/<parser+extractor_md5>/<key>.json`. Editing `hourly_profile_parser.rb` OR `anchor_extractor.rb` invalidates the cache (new combined md5 → new directory).
- The cache key includes capacity, yearly_surplus, month, year, description text — so different (entry, tier) pairs hash to different files.
- Generator-only edits (`hourly_profile_generator.rb`) reuse cached parser output → fast iteration (~10 sec for 32 cases).
- Parser/extractor edits → 32 fresh Gemini calls (~3-8 min, sometimes slower if Gemini hangs).
