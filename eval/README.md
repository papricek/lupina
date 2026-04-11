# eval/ — autoresearch harness for Lupina

This directory is the autoresearch setup that tunes Lupina's synthetic EDC generator against real customer data. It's how the last three commits worth of parameter/prompt improvements were found.

**If you're resuming this later, read this file first.** It points at everything else.

## The idea

Lupina converts a Czech one-line description of a solar/consumer installation into a 15-minute EDC CSV that should be statistically indistinguishable from real data for that installation. "How close is this to real?" is a measurable question: score every generator against a fixed set of (description, real_csv) pairs using a composite metric, then let an agent edit the generator in a loop and keep whatever lowers the score. This is [Andrej Karpathy's autoresearch](https://github.com/karpathy/autoresearch) pattern applied to a Ruby generator instead of LLM training.

Full strategy is in [AUTORESEARCH.md](AUTORESEARCH.md). It has the 6-component scoring rationale, the editable/frozen surface split, and the failure-mode analysis.

## Layout

```
eval/
├── README.md                    # this file
├── AUTORESEARCH.md              # strategy & scoring design
├── METHODOLOGY.md               # how to turn real EDC data → one-line Czech description
├── PIPELINE.md                  # 4-phase dataset build process
├── program.md                   # agent instructions for the autoresearch loop
├── journal.md                   # append-only log of every iteration
├── bin/
│   ├── extract-from-wattlink    # Phase 1 — pull real data, write dataset folders
│   ├── verify                   # Phase 3 — minitest suite, the "test"
│   └── score                    # scorer (composite of 6 metrics, LLM parse cached)
├── dataset/                     # gitignored — 50 entries × 5 files each
│   ├── MANIFEST.json
│   └── P001_est5kwp_2025_08/
│       ├── real.csv             # anonymized real EDC file
│       ├── metadata.json        # kind, capacity, month, ean_hash, …
│       ├── aggregates.json      # precomputed 24h profiles, zero hours, …
│       ├── description.txt      # Phase 2 — one-line Czech, written by agents
│       └── reasoning.txt        # annotator's classification notes
└── parse_cache/                 # gitignored — Gemini parse cache keyed by parser-file hash
    └── <parser_md5_8chars>/
        └── <desc_md5>.json
```

## The 4-phase pipeline

Each phase is idempotent and can be re-run independently. Full detail in [PIPELINE.md](PIPELINE.md).

| # | Phase | Command | Produces |
|---|---|---|---|
| 1 | Extract | `cd wattlink && bin/rails runner /path/to/lupina/eval/bin/extract-from-wattlink` | 50 folders in `eval/dataset/` + MANIFEST |
| 2 | Annotate | Claude Code agents reading [METHODOLOGY.md](METHODOLOGY.md) — one per folder or batches of 5 | `description.txt` + `reasoning.txt` in each folder |
| 3 | Verify | `eval/bin/verify` | Minitest pass/fail, 352 assertions |
| 4 | Score | `cd wattlink && bin/rails runner /path/to/lupina/eval/bin/score` | `eval/score.json` + stdout summary |

Phases 3 and 4 are independent — verify checks structure, score measures generator quality.

## The autoresearch loop (Phase 4 in a loop)

Read [program.md](program.md) for the full agent contract. Summary:

1. Read recent `journal.md` entries to see what's been tried.
2. Form ONE hypothesis, scoped to files in the editable set (edc_generator, consumption_edc_generator, solar_model, day_resolver, description_parser).
3. Edit → run `eval/bin/verify` → run `eval/bin/score`.
4. If composite improved → keep, log as `ACCEPTED`.
5. Else → `git checkout -- <file>`, log as `REJECTED`.

**Cache:** the scorer caches Gemini parses at `eval/parse_cache/<parser_hash>/<desc_hash>.json`. `parser_hash` is the first 8 chars of MD5 of `lib/lupina/description_parser.rb`, so any edit to the parser auto-invalidates the relevant cache. Editing only `edc_generator.rb` re-uses the existing cache (~1 minute per iteration). Editing `description_parser.rb` forces a fresh re-parse of all 49 entries via Gemini (~4 minutes per iteration).

**Determinism:** the scorer passes `seed: 42` to every generator call, so given the same code state, the score is deterministic.

## Running best

The top line of `journal.md` always tracks the running best. As of 2026-04-11:

```
RUNNING BEST: 0.2083 (composite, lower is better)
```

Baseline (all parameters as-shipped before any autoresearch): **0.2793**. Current: **0.2083** → **-25.4%**. 29 iterations across three sessions, 22 accepted + 7 rejected.

## What's been tuned (accepted changes in Lupina)

1. **`lib/lupina/edc_generator.rb`**
   - `assign_daily_factors`: weather factor range 0.7–1.3 → 0.1–1.9 (wider to match real cloudy/clear variance)
   - `solar_envelope`: `sin(phase)` → `sin(phase)**3.5` morning / `sin(phase)**2.5` afternoon (asymmetric — sharper morning ramp, flatter afternoon trail)

2. **`lib/lupina/description_parser.rb`** (the LLM prompt)
   - Removed "just use 1.0 or 0" binary guidance
   - Added smooth-value ratio bands (0.85+ → 1.0, 0.5-0.85 → 0.4-0.8, 0.2-0.5 → 0.2-0.5, <0.2 → 0.1-0.3)
   - Replaced binary FULL/ZERO example with three concrete smooth-profile examples
   - Added "no-all-zero workday" rule (minimum 0.1 during solar hours unless ratio < 0.05)

## What's still hard

From the journal diagnostic runs:

1. **Annotation quality** — ~15% of eval entries have description/data mismatches (P016 broken meter, P020 mislabeled, P034 "vše sežereme" contradicts real export). These cap shape_mae at ~0.5 no matter what the generator does.

2. **LLM profile granularity** — the parser produces hour-level profiles, so 15-min phenomena (lunch dips, weather edges) are unreachable.

3. **Metric pathologies** — `weekday_ratio_error` blows up on entries where real data has genuinely zero workday export (P031, P035 have ratio 1000+). The component is capped at 0.15 weighted contribution so it doesn't tank the score, but it's a real signal we're ignoring.

## How to resume the loop

**If you just want to re-score with current code:**

```bash
cd /Users/patrikjira/Work/wattlink
chruby-exec ruby-3.2.2 -- bin/rails runner /Users/patrikjira/Work/claude/lupina/eval/bin/score
```

First run re-populates the parse cache (~4 min if parser changed). Later runs ~30 seconds.

**If you want to run new iterations:**

1. Read `journal.md` tail for what's been tried and the current running best.
2. Pick a hypothesis from "What's still hard" or the "what to try next" sections in the journal.
3. Edit one file from the editable set. Keep the diff small.
4. Run `eval/bin/verify` (make sure tests still pass).
5. Run `eval/bin/score` (get the new composite).
6. Compare to running best. Accept or revert.
7. Append to `journal.md` with: hypothesis, diff, before/after scores, verdict, short explanation.

**If you need to rebuild the eval dataset** (new wattlink data, more entries, etc.):

Re-run Phase 1 per `PIPELINE.md`. Existing `real.csv` / `metadata.json` / `aggregates.json` will be overwritten; `description.txt` / `reasoning.txt` are preserved (annotations don't re-run automatically — spawn agents if needed).

**If you want to spot-check a single entry** (debug why it scores badly):

```ruby
# In a rails runner, load eval/score.json and find the worst entries,
# then compare synth vs real aggregates. See eval/journal.md session 2
# for the exact diagnostic script pattern.
```

## Guardrails

- **Never commit `eval/dataset/`** — it contains anonymized real customer data. Already in `.gitignore`.
- **Never edit `eval/bin/score`** as part of an iteration — that changes the metric, not the generator. Metric changes need a separate explicit decision.
- **Never skip the journal entry.** Every iteration, accepted or rejected, gets a paragraph. The log is how future runs avoid re-trying what already failed.
- **Don't chase marginal gains past ~5 consecutive rejected iterations.** Pause, diagnose, and pick a different component to attack.
