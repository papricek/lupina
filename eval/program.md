# Autoresearch program — Lupina generator tuning

You are an autonomous research agent tuning the Lupina EDC generator. Your job: lower the composite score reported by `eval/bin/score` by modifying the generator's code and re-measuring. Work in a loop until no more improvements can be found or a fixed number of iterations is reached.

## The score

```bash
cd /Users/patrikjira/Work/wattlink
chruby-exec ruby-3.2.2 -- bin/rails runner /Users/patrikjira/Work/claude/lupina/eval/bin/score
```

Output: overall composite (lower = better), plus 6 weighted components. Baseline to beat: **0.2793** (Sonnet/Opus 2026-04-10).

## What you may edit

- `lib/lupina/edc_generator.rb`
- `lib/lupina/consumption_edc_generator.rb`
- `lib/lupina/solar_model.rb`
- `lib/lupina/day_resolver.rb`
- New helper files under `lib/lupina/`

## What you must NOT edit

- `lib/lupina.rb` — public API (would break callers)
- `lib/lupina/configuration.rb`, `extractor.rb`, `version.rb`
- `lib/lupina/description_parser.rb` — LLM prompts are orthogonal; leave them alone
- `eval/**` — harness and data are ground truth
- `.gemspec`, `Gemfile*`, `sig/**`

## The loop

For each iteration:

1. Read the last 3 journal entries (or all if <3) from `eval/journal.md` to see what's been tried.
2. Form ONE hypothesis about what might lower the score. Be specific: which component, which file, which lines, which direction.
3. Run `eval/bin/verify` to establish current test state — if it fails, fix first before experimenting.
4. Make the edit. Keep changes small and isolated.
5. Run `eval/bin/verify` — if it fails, revert and try a different hypothesis.
6. Run `eval/bin/score`. Compare composite to running best.
7. If score improved: keep the change, update running best, append a journal entry with `ACCEPTED`.
8. If score regressed: revert the change (`git checkout -- <file>`), append a journal entry with `REJECTED` and why.
9. Go to step 1.

## Running best

Stored at the top of `eval/journal.md`. Update it whenever you accept a change. Format:

```
RUNNING BEST: 0.2793 at 2026-04-10T22:00 (initial baseline)
```

## Journal format

Append to `eval/journal.md` after each iteration:

```markdown
## iter 001 — 2026-04-10T22:10 — ACCEPTED
Hypothesis: daily factor range 0.7..1.3 → 0.6..1.4 will widen daily-total distribution
and reduce daily_total_mape.
Diff: lib/lupina/edc_generator.rb:98 (0.7 + rng.rand * 0.6 → 0.6 + rng.rand * 0.8)
Score before: 0.2793 (dmape=0.539, shape=0.691, peak=5.51, ...)
Score after:  0.2710 (dmape=0.485, shape=0.691, peak=5.51, ...)
Delta: -0.0083
Kept.
```

## Seed hypotheses (try these first if you have no ideas)

1. **Daily factor range**: currently `0.7 + rand * 0.6` (range 0.7–1.3). Real data may have wider variation. Try 0.5–1.5.
2. **Per-interval noise**: currently `0.85 + rand * 0.30` (±15%). Try ±10% or ±20%.
3. **Solar envelope peak sharpness**: the current `sin(phase)` is symmetric. Real production may have asymmetric peaks (afternoons cloudier). Try `sin(phase) ** 1.2`.
4. **Sunrise/sunset values**: the constants in `SolarModel::SOLAR_HOURS` are approximate. Check each month against real data peaks.
5. **Monthly share blending**: the formula `surp * (1 - ratio) + prod * ratio` may be wrong. Try other blends.
6. **Daily factor correlation**: currently each day is independent. Real weather is correlated (cloudy stretches). Try auto-regressive factors: `factor[t] = 0.7 * factor[t-1] + 0.3 * rand`.
7. **Variance scaling**: if `variance_ratio_error` is high, daily totals are too uniform. Increase daily factor range.

## Rules

- ONE change per iteration. Don't combine hypotheses.
- Changes must be small and isolated — if the diff is over 20 lines, split it.
- Never edit tests, data, or the scorer itself.
- Never `git commit` or `git push` from inside the loop. Keep changes in the working tree; a human promotes them later.
- If you make 5 consecutive REJECTED iterations, pause and ask the user for direction.
- Stop after 20 iterations total per run.

## Determinism

The scorer uses `seed: 42` for all generator calls, so scoring is fully deterministic given the code state. Same code → same score.

## Starting point

Current baseline: 0.2793. Component weights are in `eval/bin/score` (WEIGHTS constant). The biggest contributors are `hourly_shape_mae` (0.104 weighted) and `daily_total_mape` (0.090 weighted). Focus there first.
