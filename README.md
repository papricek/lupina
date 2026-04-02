# Lupina

Synthetic EDC data generator for Czech solar plants. Takes a natural language description of a photovoltaic installation and generates realistic 15-minute interval export files matching the EDC (Energetické datové centrum) format.

**Natural language in, realistic time-series out.**

## How it works

A solar plant with a given **capacity (kWp)** produces roughly 1 MWh per kWp per year in Czech Republic. Part of this production is consumed locally by the building/facility, and the rest is **exported to the grid** — in Czech called **přetoky**.

```
production ≈ capacity_kWp × 1000 kWh/year
přetoky (export) = production − local consumption
```

The customer provides:

1. **Capacity (kWp)** — peak power of the solar plant, determines total production
2. **Yearly export (přetoky)** — last year's total export to grid in kWh, used to calibrate monthly predictions
3. **Export characteristics** — natural language description of when export happens (e.g. "only afternoons and weekends", "everything goes to grid")

Lupina uses the Gemini LLM to extract these parameters and generate an **export profile** — a 24-hour pattern describing what fraction of production is exported at each hour, separately for workdays, Saturdays, and Sundays.

The generator then distributes the monthly export total across 15-minute intervals, shaped by:
- **Export profile** — when export happens (from consumption characteristics)
- **Solar envelope** — sin curve between sunrise/sunset for the given month (50°N latitude)
- **Seasonal weighting** — summer months get more export than winter
- **Daily variation** — ±30% per day for realistic day-to-day differences

The output is a CSV in the standard EDC format:

```
Datum;Cas od;Cas do;IN-859182400110224391-D;OUT-859182400110224391-D
01.07.2026;00:00;00:15;0,0;0,0;
01.07.2026;12:00;12:15;8,93;8,93;
...
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lupina'
```

And then execute:

    $ bundle install

## Usage

### From natural language (recommended)

The simplest way — describe the installation in plain Czech and let the LLM handle everything:

```ruby
require 'lupina'

Lupina.configure do |config|
  config.gemini_api_key = ENV['GEMINI_API_KEY']
end

result = Lupina.from_description(
  "100 kWp, přetoky 30 MWh za rok, přes týden vše sežereme, max polední pauza",
  month: 7, year: 2026, seed: 42
)

File.write("output.csv", result[:csv])
puts result[:stats]
# => { month: 7, year: 2026, days: 31, capacity_kwp: 100.0,
#      total_surplus_kwh: 4680.0, total_production_kwh: 13500.0, ... }
puts result[:parsed]["reasoning"]
```

### With explicit export profile

You can also provide the export profile directly, without the LLM:

```ruby
# Export profile: fraction of production exported at each hour (0.0–1.0)
# The generator applies the solar envelope automatically — just say when export happens.
full_day = Array.new(24, 1.0)
afternoon_only = Array.new(24) { |h| h >= 14 && h <= 20 ? 1.0 : 0.0 }

result = Lupina.generate_edc(
  capacity_kwp: 100,
  yearly_surplus_kwh: 50_000,
  month: 7,
  year: 2026,
  surplus_profile: {
    workday:  afternoon_only,  # export only after shift ends at 14:00
    saturday: full_day,        # full export all day
    sunday:   full_day         # full export all day
  },
  ean: "859182400110224391",
  seed: 42
)
```

If `surplus_profile` is omitted, defaults to full export (all 1.0) — all production goes to grid.

### Consumption EDC

For consumption profiles (no solar plant, just a consumer):

```ruby
result = Lupina.generate_consumption_edc(
  yearly_consumption_kwh: 25_000,
  month: 7,
  year: 2026,
  consumption_profile: {
    workday:  Array.new(24) { |h| h >= 3 && h <= 10 ? 1.0 : 0.05 },  # bakery 3-11am
    saturday: Array.new(24) { |h| h >= 3 && h <= 9 ? 1.0 : 0.05 },   # shorter Saturday
    sunday:   Array.new(24, 0.05)                                       # closed
  },
  seed: 42
)
```

Or via natural language — `from_description` handles both production and consumption automatically:

```ruby
result = Lupina.from_description("pekárna, spotřeba 25 MWh ročně, jedou od 3 do 11 ráno", month: 7)
# result[:stats] => { total_consumption_kwh: 2123.3, peak_consumption_kw: 14.4, ... }
```

## Parameters

### `generate_edc` (production/export)

| Parameter | Description |
|---|---|
| `capacity_kwp` | Peak capacity of the solar plant in kWp |
| `yearly_surplus_kwh` | Total energy exported to grid per year in kWh (přetoky). Must not exceed capacity × 1000. |
| `month` | Month to generate (1-12) |
| `year` | Year (default: current year) |
| `surplus_profile` | Hash with 7 weekday keys (`:monday` through `:sunday`), each an array of 24 floats (0.0–1.0). Optional — defaults to full export. |
| `ean` | EAN identifier for the metering point |
| `seed` | Random seed for reproducible output |

### `generate_consumption_edc` (consumption)

| Parameter | Description |
|---|---|
| `yearly_consumption_kwh` | Total energy consumed per year in kWh |
| `month` | Month to generate (1-12) |
| `year` | Year (default: current year) |
| `consumption_profile` | Hash with 7 weekday keys (`:monday` through `:sunday`), each an array of 24 floats (0.0–1.0). Optional — defaults to flat. |
| `ean` | EAN identifier for the metering point |
| `seed` | Random seed for reproducible output |

## Example descriptions

Each example shows a natural language description as it would come from a customer. The LLM extracts capacity, yearly export, and generates the export profile automatically.

**Production (solar plant)** — has capacity in **kWp** and yearly přetoky (export) in **MWh**:

---

### 1. Barn rooftop, no one lives there
> "15 kWp na stodole, nikdo tam nebydlí, přetoky 14 MWh ročně"

Export ratio: 14/15 = 93% — almost everything exported. Profile: all 1.0.

```ruby
Lupina.from_description("15 kWp na stodole, nikdo tam nebydlí, přetoky 14 MWh ročně", month: 7)
```

### 2. Factory with lunch break
> "100 kWp, přetoky 30 MWh za rok, přes týden vše sežereme, max polední pauza když kluci vypnou mašiny"

Export ratio: 30/100 = 30% — high consumption. Workday export only during lunch (12-13) + weekends.

```ruby
Lupina.from_description("100 kWp, přetoky 30 MWh za rok, přes týden vše sežereme, max polední pauza", month: 7)
```

### 3. Workshop with early morning shift
> "100 kWp, přetoky 50 MWh za rok, výroba jede od 6 do 14, víkend plné přetoky"

Export ratio: 50/100 = 50%. Workday export from 14:00 onwards + full weekends.

```ruby
Lupina.from_description("100 kWp, přetoky 50 MWh za rok, výroba jede od 6 do 14, víkend plné přetoky", month: 8)
```

### 4. Solar farm on a meadow
> "250 kWp na louce, jen trafostanice žere něco, přetoky 230 MWh ročně"

Export ratio: 230/250 = 92% — minimal consumption. Profile: all 1.0.

```ruby
Lupina.from_description("250 kWp na louce, jen trafostanice žere něco, přetoky 230 MWh ročně", month: 6)
```

### 5. Office building rooftop
> "50 kWp na střeše kanceláří, přetoky hlavně odpoledne a celý víkend, 20 MWh za rok"

Export ratio: 20/50 = 40%. Workday export from ~15:00 + full weekends.

```ruby
Lupina.from_description("50 kWp na střeše kanceláří, přetoky hlavně odpoledne a celý víkend, 20 MWh za rok", month: 5)
```

---

**Consumption (customer)** — has yearly consumption in **MWh**. The LLM extracts the consumption total and generates a consumption profile (when energy is consumed). No solar envelope — consumption can happen at any hour.

### 6. Family house
> "rodinný dům, 4 MWh ročně, lidi v práci přes den, spotřeba hlavně večer a ráno"

Morning peak 6-8, low daytime, evening peak 17-21. Weekend spread more evenly.

```ruby
Lupina.from_description("rodinný dům, 4 MWh ročně, lidi v práci přes den, spotřeba hlavně večer a ráno", month: 7)
```

### 7. Small bakery
> "pekárna, spotřeba 25 MWh ročně, jedou od 3 do 11 ráno, pak zavřeno"

Peak 3-11am (ovens), standby rest of day. Shorter Saturday, closed Sunday.

```ruby
Lupina.from_description("pekárna, spotřeba 25 MWh ročně, jedou od 3 do 11 ráno, pak zavřeno", month: 7)
```

### 8. Apartment building
> "bytovka, 8 MWh ročně, výtahy a osvětlení, celkem rovnoměrná spotřeba"

Roughly flat profile with slight morning/evening peaks (elevator usage).

```ruby
Lupina.from_description("bytovka, 8 MWh ročně, výtahy a osvětlení, celkem rovnoměrná spotřeba", month: 7)
```

### 9. Welding shop
> "zámečnická dílna, spotřeba 60 MWh ročně, svářečky a kompresory jedou 7-17, víkend zavřeno"

Peak 7-17 workdays, standby weekends.

```ruby
Lupina.from_description("zámečnická dílna, spotřeba 60 MWh ročně, svářečky a kompresory jedou 7-17, víkend zavřeno", month: 7)
```

### 10. Cow barn
> "kravín, spotřeba 40 MWh za rok, dojení a krmení 4-10h, pak jen chlazení mléka"

Peak 4-10 (milking), base load daytime (cooling), same every day.

```ruby
Lupina.from_description("kravín, spotřeba 40 MWh za rok, dojení a krmení 4-10h, pak jen chlazení mléka", month: 7)
```

## Sample EDC files

Pre-generated EDC files (July 2026) for 10 diverse scenarios — download and inspect:

**Production (export):**
- [P1 — Supermarket 200 kWp, 40 MWh](examples/scenarios/P1_supermarket_07_2026.csv) — low export ratio (20%), workday noon only + weekend afternoon
- [P2 — Garage 30 kWp, 27 MWh](examples/scenarios/P2_garaz_07_2026.csv) — high export ratio (90%), full export all day
- [P3 — Sawmill 80 kWp, 15 MWh](examples/scenarios/P3_pila_07_2026.csv) — very low ratio (19%), workday after 16h + Sunday
- [P4 — Auto repair 45 kWp, 25 MWh](examples/scenarios/P4_autoservis_07_2026.csv) — medium ratio (56%), workday after 16h + weekends
- [P5 — School 150 kWp, 100 MWh](examples/scenarios/P5_skola_07_2026.csv) — high ratio (67%), workday after 15h + weekends

**Consumption:**
- [C1 — Server room 120 MWh](examples/scenarios/C1_serverovna_07_2026.csv) — flat 24/7
- [C2 — Restaurant 35 MWh](examples/scenarios/C2_restaurace_07_2026.csv) — Tue-Sat 9-22, closed Sun+Mon
- [C3 — Fitness 50 MWh](examples/scenarios/C3_fitness_07_2026.csv) — bimodal 6-9 + 16-22
- [C4 — Night bakery 30 MWh](examples/scenarios/C4_nocni_pekarna_07_2026.csv) — peak 22-06, low daytime
- [C5 — Small shop 8 MWh](examples/scenarios/C5_obchod_07_2026.csv) — Mon-Sat 8-18, Sunday off

See [scenarios.md](scenarios.md) for full Czech descriptions and expected behavior of each scenario.

## Generator model

### Production (export)

Uses a parametric solar model for Czech Republic (50°N):

- **Seasonal distribution** — monthly production shares from January (2.5%) to June (14%) peak
- **Monthly export allocation** — blends production curve with a surplus-weighted curve based on the export/production ratio. High ratio (barn) follows production; low ratio (factory) concentrates export in summer.
- **Solar envelope** — sine curve between sunrise/sunset per month (accounts for DST)
- **Daily variation** — ±30% random factor per day for realistic differences
- **Intra-day noise** — ±15% per 15-minute interval

Typical specific yield: ~1000 kWh/kWp/year.

### Consumption

Simpler model — no solar dependency:

- **Monthly allocation** — proportional to days in month (no seasonal weighting)
- **Consumption profile** — LLM-generated 24-hour pattern describes when consumption happens (can be any hour, including night)
- **Daily variation** — ±30% random factor per day
- **Intra-day noise** — ±15% per 15-minute interval

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt.

```ruby
# In bin/console:
result = Lupina.generate_edc(capacity_kwp: 100, yearly_surplus_kwh: 30_000, month: 7, seed: 42)
puts result[:stats]
```

See `examples/` for more usage scripts.
