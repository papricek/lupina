# Eval dataset pipeline

Repeatable process for building, annotating, and verifying the Lupina eval dataset. Run any phase independently; each is deterministic given the inputs from the previous phase.

## Layout

```
lupina/eval/
├── METHODOLOGY.md              # how to transform EDC → description
├── PIPELINE.md                 # this file
├── bin/
│   ├── extract-from-wattlink   # phase 1 extractor (rails runner script)
│   └── verify                  # phase 3 minitest verifier — the "test"
└── dataset/
    ├── MANIFEST.json           # index of all entries
    ├── P001_est5kwp_2025_08/
    │   ├── real.csv            # phase 1
    │   ├── metadata.json       # phase 1
    │   ├── aggregates.json     # phase 1
    │   ├── description.txt     # phase 2
    │   └── reasoning.txt       # phase 2
    └── ...
```

Everything lives in the lupina gem. Wattlink is only referenced as a data source — the extractor is a plain Ruby file that happens to use ActiveRecord, executed via `rails runner` from wattlink's bundle context.

## Phase 1 — Extract (wattlink)

Pulls real EDC readings from the wattlink DB, anonymizes EANs, and writes one folder per entry to `lupina/eval/dataset/`. The script lives in lupina but runs under wattlink's Rails environment for DB access.

```bash
cd /Users/patrikjira/Work/wattlink
chruby-exec ruby-3.2.2 -- bin/rails runner \
  /Users/patrikjira/Work/claude/lupina/eval/bin/extract-from-wattlink
```

Selection (current defaults — edit the script to change):
- **Production**: 35 suppliers, diversified by peak power, month with max output picked per EAN. Requires `sum(final) > 1000 kWh` and `max(final) > 0.5 kWh/15min`. Capacity is **estimated** from peak: `ceil(peak_kw × 1.15)`, flagged `capacity_source: "estimated_from_peak"` in metadata.
- **Consumption**: 15 customers, diversified by total consumption. Requires `sum(abs(original)) > 500 kWh`. Values abs-ed since raw data is signed negative.

Output per entry:
- `real.csv` — Lupina EDC format (`Datum;Cas od;Cas do;IN-<synthetic_ean>-D;OUT-<synthetic_ean>-D`), comma decimal separator, 2880–2976 rows
- `metadata.json` — `{id, kind, capacity_kwp, capacity_source, yearly_*_estimated, month, year, days_in_month, rows, city, ean_hash, synthetic_ean}`
- `aggregates.json` — precomputed stats: 24h workday/weekend averages (IN + OUT), per-weekday daily totals, zero-hour lists, peak power
- `MANIFEST.json` — top-level index listing all entries

**Idempotency**: re-running overwrites existing folders. Back up first if you have human-reviewed descriptions you want to keep.

**Changing size**: edit `TARGET_PRODUCTION` and `TARGET_CONSUMPTION` at the top of `eval/bin/extract-from-wattlink`.

## Phase 2 — Annotate

Each folder needs `description.txt` + `reasoning.txt` written according to `METHODOLOGY.md`.

**Current approach** — Claude Code agent batches. Dispatch 10 parallel agents, each handling 5 folders. Each agent reads `metadata.json` + `aggregates.json`, applies the 6-step framework, and writes the two text files. Wall clock: ~2 minutes for 50 entries.

Agent prompt template is in `METHODOLOGY.md` under "Worker instructions". Example invocation from Claude Code:

> *"Dispatch 10 parallel agents, each annotating 5 folders in `lupina/eval/dataset/` according to `METHODOLOGY.md`. Folders to assign: [list]. Each agent writes `description.txt` + `reasoning.txt` per folder and reports the 5 final lines."*

**Future approach** — `eval/bin/annotate` script using `ruby_llm` to call Gemini or Claude directly per folder. Not yet implemented; would let Phase 2 run non-interactively as part of the pipeline. Skeleton:

```ruby
Dir.glob("eval/dataset/[CP]*/") do |folder|
  next if File.exist?(File.join(folder, "description.txt"))  # idempotent
  metadata = JSON.parse(File.read(File.join(folder, "metadata.json")))
  aggregates = JSON.parse(File.read(File.join(folder, "aggregates.json")))
  prompt = build_annotation_prompt(metadata, aggregates)
  response = RubyLLM.chat(model: "gemini-2.0-flash").ask(prompt)
  File.write(File.join(folder, "description.txt"), response.parsed[:description])
  File.write(File.join(folder, "reasoning.txt"), response.parsed[:reasoning])
end
```

## Phase 3 — Verify (the "test")

Runs a Minitest suite with ~7 assertions per folder.

```bash
cd /Users/patrikjira/Work/claude/lupina
eval/bin/verify
```

Checks per entry:

1. **Required files present and non-empty** — `real.csv`, `metadata.json`, `aggregates.json`, `description.txt`, `reasoning.txt`
2. **Metadata schema** — required keys by kind, valid month/year, rows ≥ 2800, capacity > 0 for production
3. **Aggregates schema** — scalars, 24-element hourly arrays, weekday hashes with keys 0–6, hour lists bounded 0–23
4. **CSV format** — Lupina header, ≥ 2800 data rows, row regex match, row count matches metadata
5. **Description well-formed** — non-empty, single line, 5–250 chars, mentions `kWp`/`přetoky` (production) or `spotřeba` (consumption)
6. **Reasoning well-formed** — bullet points, contains `→` pointing to final description
7. **Capacity sanity** (production only) — yearly_surplus / (capacity × 1000) ≤ 1.10. Catches absurd estimates.

Plus 2 global checks: dataset root exists, `MANIFEST.json` matches folder count.

Exit code: 0 if all pass, 1 if any fail. Failures report which entry and what's wrong.

Total: ~350 assertions, runs in under a second.

## Phase 4 — Human review

Automated checks don't catch *whether* a description is correct — only that it's well-formed. Review each description against its aggregates:

- Does it match the actual dominant pattern?
- Does it follow style rules (colloquial, no guessed business types, concrete times)?
- Would a Czech customer plausibly say this?
- Is the classification in `reasoning.txt` consistent with the data?

Flag bad entries and re-run Phase 2 on those specific folders.

## Re-running after data changes

**New readings arrive in wattlink:**
1. Re-run Phase 1 → new/updated folders
2. For new entries, run Phase 2 (existing descriptions preserved if annotator is idempotent)
3. Run Phase 3 to verify the whole set

**Methodology changes** (new style rule, new metric component):
1. No re-extraction needed; Phase 1 output is stable
2. Rewrite affected descriptions (Phase 2 on subset)
3. Run Phase 3

**Changing selection criteria**:
1. Edit `TARGET_PRODUCTION` / `TARGET_CONSUMPTION` or the SQL filters in `build_eval_dataset.rb`
2. Re-run Phase 1 (overwrites everything)
3. Re-run Phase 2 (full)
4. Run Phase 3

## Known data quality issues (from first run)

- **P033** (551 kWp, Vejprnice, Dec 2025): export ratio 17.8× theoretical max. Likely aggregated multi-EAN or mislabeled meter. **Verify catches this** via `test_P033_07_capacity_sane_for_production`. Should be dropped or investigated.
- **P016** (34 kWp, March, 1 MWh/yr): sparse but honest. Borderline usable.
- **P024** (63 kWp, Zlín): ratio < 0.03 — practically no export. Either massive self-consumption or data issue. Worth verifying.

When verify flags an entry, the typical response is: drop it from `MANIFEST.json`, remove the folder, re-run verify.

## Summary

| Phase | Input | Output | Command | Deterministic? |
|---|---|---|---|---|
| 1 Extract | wattlink DB | 50 folders + MANIFEST | `rails runner eval/bin/extract-from-wattlink` | Yes (given DB state) |
| 2 Annotate | folder's 2 JSONs | `description.txt` + `reasoning.txt` | agent dispatch or `eval/bin/annotate` (future) | LLM-non-deterministic |
| 3 Verify | dataset folders | pass/fail report | `eval/bin/verify` | Yes |
| 4 Review | everything | list of bad entries | human | — |
