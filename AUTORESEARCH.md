# Autoresearch for Lupina

Applying Andrej Karpathy's [autoresearch](https://github.com/karpathy/autoresearch) pattern to make Lupina's synthetic EDC data statistically indistinguishable from real Czech EDC files given a natural-language description.

## Goal

Given a Czech one-line description of a solar installation or consumer (e.g. *"100 kWp, přetoky 30 MWh ročně, přes týden vše sežereme"*), Lupina should produce a 15-minute EDC CSV whose statistical fingerprint matches what a real meter at that installation would record.

Current state: the generator is plausible but visibly synthetic. Monthly totals match, shapes look right, but fine-grained behavior (ramps, noise structure, weather dips, DST edges, weekend/workday balance) is not calibrated to reality. We have no systematic measurement of "how close to real is this?".

## Why autoresearch fits

Lupina's improvement loop is a search problem with three clean ingredients:

1. **Bounded editable surface** — the generator is a handful of Ruby files with a tight public API. An agent can modify them in isolation without touching callers.
2. **Deterministic scoring** — given a fixed eval set of (description, real_csv) pairs, generating and scoring is a ~minute-scale operation in Ruby with no GPU required.
3. **Single scalar to minimize** — a weighted distance between generated and real time series, averaged across the eval set. Lower = better.

Unlike LLM training (Karpathy's original domain), Lupina experiments are **cheap**: no GPU, no minutes-long compile, generation + scoring finishes in seconds per scenario. That means the iteration count can be much higher — potentially hundreds of experiments per hour — so the signal-to-noise tradeoff on the time budget is much more favorable than in ML training.

## The loop

```
for each iteration:
  1. Agent reads current generator code + last N experiment results
  2. Forms a hypothesis ("noise should be correlated within a day",
     "monthly shares should be different for consumption vs production", ...)
  3. Edits files in the editable surface
  4. Runs `bin/eval` against validation set
  5. Compares composite score to running best
  6. Keeps the change if score improved, reverts otherwise
  7. Logs the hypothesis, diff, score, and decision
```

## Editable surface

The agent may freely modify these files:

- `lib/lupina/edc_generator.rb` — production distribution, daily factors, noise
- `lib/lupina/consumption_edc_generator.rb` — consumption variant
- `lib/lupina/solar_model.rb` — monthly shares, sunrise/sunset, specific yield
- `lib/lupina/description_parser.rb` — LLM prompt and post-processing
- `lib/lupina/day_resolver.rb` — weekday/holiday/shutdown mapping
- New helper files under `lib/lupina/` are allowed

The agent may **not** modify:

- `lib/lupina.rb` — public API surface (would break callers)
- `lib/lupina/configuration.rb`, `extractor.rb`, `version.rb`
- Anything under `eval/` — eval harness and test data are ground truth
- `sig/`, `lupina.gemspec`, `Gemfile*`

## Scoring metric

A single scalar `composite_score` computed per (description, real_csv) pair, then averaged across the eval set. Lower is better.

Components (all computed on 15-min EDC series aligned by timestamp):

| Component | What it measures | Weight |
|---|---|---|
| `daily_total_mape` | Mean absolute percentage error of daily kWh totals | 0.25 |
| `hourly_shape_mae` | MAE on normalized 24-hour average profile (workday + weekend separately) | 0.30 |
| `peak_time_delta` | Absolute difference in hour-of-peak between real and synthetic daily average | 0.10 |
| `weekday_ratio_error` | Absolute error on weekend/workday total ratio | 0.15 |
| `autocorr_distance` | L2 distance between lag-1 autocorrelation of both series | 0.10 |
| `variance_ratio_error` | `|log(var_synth / var_real)|` across daily totals | 0.10 |

The composite is the weighted sum. Raw components are also logged so the agent can see where it's losing.

**Deliberately NOT in the score:**
- 15-min-level MAE (too noisy, rewards overfitting to specific intervals)
- Exact peak value (real data has weather noise we can't reproduce)
- LLM parse quality (graded separately; orthogonal concern)

## Eval dataset

We need N pairs of:

1. **Real EDC CSV** for one month at one EAN, 15-min intervals
2. **Short Czech description** matching what the customer would say about that installation
3. **Metadata**: capacity_kwp (for production), yearly_surplus_kwh or yearly_consumption_kwh, kind (production/consumption), month, year

Target: **30–60 pairs**, spanning:
- Both kinds (production + consumption)
- Capacity range: ~10 kWp residential → ~500 kWp commercial
- Seasons: winter (Dec–Feb), shoulder (Mar, Oct), summer (Jun–Aug)
- Diverse consumption patterns: always-on (cow barn), workday-only (factory), weekend-only (cottage), bimodal (bakery)

Source: wattlink scrapes real EDC files from the portal for real customers. Those CSVs can be exported and anonymized (strip EAN, rename to sequential IDs). Descriptions are written by a domain expert based on known facts about each installation (or reconstructed from customer-supplied info in the CRM).

Store at `eval/dataset/` with structure:
```
eval/dataset/
  P001_barn_15kwp_07_2025/
    description.txt        # one Czech line
    metadata.json          # capacity, yearly, kind, month, year
    real.csv               # real EDC file
  P002_factory_100kwp_11_2025/
    ...
  C001_bakery_35mwh_03_2025/
    ...
```

### Splits

- **Train (60%)** — agent iterates freely, allowed to look at these
- **Validation (25%)** — used for the accept/reject decision each iteration
- **Test (15%)** — held out completely, only scored at the end of a run to detect overfitting

Splits are fixed up-front in `eval/splits.json` and never regenerated within a run.

## Eval harness

Single script at `bin/eval` (to be written):

```bash
bin/eval --split validation        # score current code on validation set
bin/eval --split train             # score on train
bin/eval --split test              # held-out, use sparingly
bin/eval --scenario P001_barn      # debug single scenario
bin/eval --output-json eval.json   # structured output for the agent
```

Outputs:
- Composite score (single number)
- Per-component breakdown
- Per-scenario scores
- Per-scenario diagnostic plots (optional, for human review)

Constraints:
- Deterministic: same code + same seed ⇒ same score (eliminate `Random.new` without seed in eval path)
- Fast: full validation set in under 2 minutes, ideally under 30 seconds
- Isolated: no network calls during scoring (cache LLM description parses — see below)

### LLM parse caching

`Lupina.parse_description` hits Gemini, which is slow and non-deterministic. During eval:

1. First run: call Gemini once per description, cache the parsed JSON at `eval/parse_cache/<hash>.json`
2. Subsequent runs: load from cache, skip LLM entirely
3. When the agent modifies `description_parser.rb`, it must invalidate the cache (rerun parses)

This means the scorer measures the **generator**, not the LLM parse, unless the agent explicitly changes the parser. Orthogonalizing these two concerns keeps the signal clean.

## Program.md (agent instructions)

The agent is steered by `program.md` at the repo root, following the Karpathy convention. It should contain:

- The goal (what "better" means)
- The editable surface (what it may touch)
- The loop contract (read → hypothesize → edit → score → decide)
- The command to run eval (`bin/eval --split validation --output-json ...`)
- Rules: always keep generator deterministic given a seed; never edit test data; don't touch public API
- Ideas to explore (seed hypotheses for the first few iterations)
- Running log format (append-only journal at `eval/journal.md`)

## Steps to start

### Phase 1 — build the harness (human work, no agent yet)

1. **Collect 30–60 real EDC files** from wattlink's scraped data. Anonymize EANs. One month per file, mixed seasons.
2. **Write descriptions** for each installation — one Czech line each, matching how a customer would describe it. Reuse the style from `README.md` examples.
3. **Fill metadata** (capacity, yearly total, kind, month, year) from CRM or customer records.
4. **Write `bin/eval`** — loader, scorer, composite metric, JSON output.
5. **Fix the splits** — randomly partition 60/25/15, store the assignment.
6. **Cache LLM parses** — run `parse_description` once per training description, store at `eval/parse_cache/`.
7. **Baseline** — run `bin/eval --split validation` against current `main` and record the baseline composite score. This is the number autoresearch must beat.

Phase 1 deliverable: a repeatable command that produces a single number, plus the baseline value.

### Phase 2 — write `program.md` and do a dry run

1. **Draft `program.md`** with goal, rules, and 5–10 seed hypotheses (e.g. *"try removing per-interval noise and see if variance matches better"*).
2. **Single-iteration dry run** — manually ask Claude Code to read `program.md`, make one change, run `bin/eval`, report. Verify the loop is functional end-to-end before going autonomous.
3. **Fix any harness bugs** found during the dry run.

### Phase 3 — autonomous run

1. **Kick off an overnight run** — Claude Code in autonomous mode pointed at `program.md`.
2. **Morning review** — read `eval/journal.md`, inspect accepted diffs, verify no overfitting by scoring on the held-out test set.
3. **Promote wins** — cherry-pick accepted changes into actual commits with proper messages. Don't merge the agent's raw journal branch.

### Phase 4 — iterate

- Expand the eval set as coverage gaps become obvious.
- Add new metric components if the agent games the current ones.
- Rerun with a fresh `program.md` on a new seed hypothesis set.

## Risks and anti-patterns

- **Overfitting to the validation set.** Mitigation: held-out test set, never scored during a run.
- **Gaming the metric.** If the agent discovers a degenerate solution (e.g. always output the per-scenario mean), the metric has a blind spot. Mitigation: composite of independent components; inspect diffs, not just scores.
- **Description bias.** If all eval descriptions come from one writer, the agent overfits to that writer's phrasing. Mitigation: at least 2–3 people writing descriptions.
- **Eval drift from LLM non-determinism.** The description parser is an LLM and drifts across Gemini versions. Mitigation: parse cache (above), versioned and checked in.
- **Seasonal leakage.** Train/val/test must not share the same installation across splits — an installation appears in exactly one split, otherwise the agent learns the installation's fingerprint instead of general structure.
- **Optimizing the wrong thing.** The composite score is an approximation of "realistic". Periodically, a human should look at a generated CSV side-by-side with the real one for a test scenario and ask "would a domain expert think these are the same installation?". If the composite says yes and the human says no, the metric is broken and needs new components.

## Expected outcome

A better-calibrated Lupina that:

- Produces daily totals with realistic variance (not too smooth, not too noisy)
- Gets weekend/workday balance right for the described pattern
- Has correct peak timing and peak magnitude distribution
- Handles shoulder-season ambiguity (March, October) without over/undershooting
- Respects capacity ceilings without explicit clamping

Quantitatively: composite score on the test set meaningfully below baseline, with each of the 6 components individually at least non-worse.

The technique is not a silver bullet — it finds local improvements on a fixed metric. Architectural shifts (e.g. moving to a learned model, adding real weather data) still require human decisions. Autoresearch's job is to exhaust the tuning space on whatever architecture currently exists.
