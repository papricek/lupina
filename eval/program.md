# Autoresearch program — Lupina generator tuning (V3 dataset)

You are an autonomous research agent tuning the Lupina EDC generator. Your job: lower the composite score reported by `eval/bin/score` by modifying the generator's code and re-measuring. Work in a loop until no more improvements can be found or a fixed number of iterations is reached.

## The score

```bash
cd /Users/patrikjira/Work/wattlink
chruby-exec ruby-3.2.2 -- bin/rails runner /Users/patrikjira/Work/claude/lupina/eval/bin/score
```

Output: overall composite (lower = better), per-tier composite (4 tiers), per-entry composite (8 entries), 6 weighted components.

**Baseline to beat: 0.3255** (V3 dataset, unmodified lupina at the commit that introduced the V3 harness).

## Dataset shape

- 8 EAN-month pairs × 4 description tiers = **32 cases per iteration**
- Tiers: `popis` (technical short), `popis_2` (technical medium), `popis_laik` (layman), `popis_zkuseny` (expert with numbers)
- Real CSVs from wattlink `edc_readings`, March/April 2026
- xlsx "Přetoky (MWh)" column = yearly export, fed directly to lupina (capped at capacity_kwp × 999)
- ⚠ Several entries (V3_01, V3_02, V3_03, V3_08) have ~10× xlsx-vs-measured discrepancy on yearly export. This dominates `daily_total_mape` and is real dataset signal, not a bug.

## What you may edit

- `lib/lupina/edc_generator.rb`
- `lib/lupina/consumption_edc_generator.rb`
- `lib/lupina/solar_model.rb`
- `lib/lupina/day_resolver.rb`
- `lib/lupina/description_parser.rb` — LLM prompt + post-processing. Edits invalidate the parse cache automatically (cache key includes parser-file MD5), so every iteration that touches the parser re-runs ~32 unique Gemini calls (~3–5 min wall clock).
- New helper files under `lib/lupina/`

## What you must NOT edit

- `lib/lupina.rb` — public API (would break callers)
- `lib/lupina/configuration.rb`, `extractor.rb`, `version.rb`
- `eval/**` — harness and data are ground truth
- `.gemspec`, `Gemfile*`, `sig/**`

## The loop

For each iteration:

1. Read the last 3 journal entries (or all if <3) from `eval/journal.md` to see what's been tried.
2. Form ONE hypothesis about what might lower the score. Be specific: which component, which file, which lines, which direction. Look at the per-tier or per-entry breakdown to target where the algorithm is weakest.
3. Run `eval/bin/verify` to establish current test state — if it fails, fix first before experimenting.
4. Make the edit. Keep changes small and isolated (≤20 lines diff).
5. Run `eval/bin/verify` — if it fails, revert (`git checkout -- <file>`) and try a different hypothesis.
6. Run `eval/bin/score`. Compare composite to running best.
7. **If score improved**:
   - Keep the change.
   - Update RUNNING BEST in `eval/journal.md`.
   - Append a journal entry with `ACCEPTED` (see format below).
   - **`git commit` the change with a short message describing the hypothesis and the score delta.** This is required — every accepted iteration becomes its own commit so the research history is replayable.
8. **If score regressed**:
   - Revert the change (`git checkout -- <file>`).
   - Append a journal entry with `REJECTED` and a short reason.
   - Do NOT commit on rejection.
9. Go to step 1.

## Commit format

After step 7, commit with:

```bash
git -C /Users/patrikjira/Work/claude/lupina add lib/lupina/<file>.rb eval/journal.md
git -C /Users/patrikjira/Work/claude/lupina commit -m "iter NNN: <hypothesis short> (-0.0XXX)"
```

Stage only the lupina source files you edited and `eval/journal.md`. Do NOT stage `eval/score.json` (regenerated every run) or anything under `eval/dataset/` or `eval/parse_cache/` (gitignored).

## Journal format

Append to `eval/journal.md` after each iteration:

```markdown
## iter 001 — 2026-05-06T22:10 — ACCEPTED
Hypothesis: <one or two sentences. Which component, which file, which knob, which direction>
Diff: <file:line, brief description, e.g. "edc_generator.rb:98 daily factor range 0.7..1.3 → 0.6..1.4">
Score before: 0.3255 (dmape=5.41, shape=0.54, peak=1.80, ratio=0.37, acf=0.09, var=1.25)
Score after:  0.3210 (dmape=4.98, shape=0.54, peak=1.80, ratio=0.36, acf=0.09, var=1.20)
Delta: -0.0045
Per-tier deltas: popis -0.005  popis_2 -0.004  popis_laik -0.005  popis_zkuseny -0.004
Commit: <short sha>
```

For REJECTED entries, omit the commit line and add a one-sentence "Why" line.

## Seed hypotheses (try these first if you have no ideas)

The biggest weighted contributor is `daily_total_mape` (raw 5.41, weighted at 0.250 cap). Several entries have xlsx-yearly that's ~10× higher than measured monthly suggests — meaning lupina spreads too much energy into each day. Tunes that help here move the most score.

1. **Self-consumption fudge in description_parser**: when a description says "domácnost" or "vlastní spotřeba minimální" or names a small kWp, the parser could scale `yearly_surplus_kwh` down rather than passing it through unchanged. Aim: bring synthetic monthly closer to real monthly without changing `MONTHLY_SURPLUS_SHARE`.
2. **Per-tier robustness**: if one tier (e.g. `popis_laik`) scores worse than `popis_zkuseny`, the parser is brittle to vague input — sharpen ratio bands in the prompt.
3. **Solar envelope asymmetry** (`edc_generator.rb`): currently 3.5 morning / 2.5 afternoon. Czech April has long afternoons; try 3.0/3.0 or 4.0/2.0.
4. **`MONTHLY_SURPLUS_SHARE`** (`solar_model.rb`): March=0.060 and April=0.090 in the current table. If real April export is consistently ~10× lower than `yearly × 0.090`, the share for April may be too high relative to summer months.
5. **Daily factor range**: currently `0.1 + rand * 1.8` (0.1..1.9). Real April had cloudy stretches; try widening or adding AR(1) correlation.
6. **Sunrise/sunset DST**: April 2026 spans DST. Confirm `SOLAR_HOURS[4]` corresponds to local time after DST jump.

## Rules

- ONE change per iteration. Don't combine hypotheses.
- Changes must be small and isolated — if the diff is over 20 lines, split it.
- Never edit tests, data, or the scorer itself.
- **Commit every ACCEPTED iteration.** No commit on REJECTED.
- Never `git push` from inside the loop.
- If you make 5 consecutive REJECTED iterations, pause and ask the user for direction.
- Stop after 20 iterations total per run.

## Determinism

The scorer uses `seed: 42` for all generator calls, so scoring is fully deterministic given the code state. Same code → same score.

## Cache

Parse cache lives at `eval/parse_cache/<parser_md5>/<description_md5>.json`. Editing
`description_parser.rb` invalidates the cache (new parser_md5 → new directory) and
re-runs the LLM for every (entry × tier) description pair = 32 Gemini calls per
parser-touching iteration. Editing only the generator/solar code reuses the cache.
