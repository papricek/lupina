# Lupina

Synthetic EDC data generator for Czech solar plants. Takes a natural language description of a photovoltaic installation and generates realistic 15-minute interval export files matching the EDC (Energetické datové centrum) format.

**Natural language in, realistic time-series out.**

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lupina'
```

And then execute:

    $ bundle install

## How it works

1. You describe a solar installation in plain Czech/English — capacity, yearly surplus, consumption pattern
2. Lupina maps that to a parametric solar model (50°N latitude, Czech weather, seasonal curves)
3. It generates a month of 15-min interval data calibrated to match the yearly totals

The output is a CSV in the standard EDC format:

```
Datum;Cas od;Cas do;IN-859182400110224391-D;OUT-859182400110224391-D
01.07.2026;00:00;00:15;0,0;0,0;
01.07.2026;12:00;12:15;8,93;8,93;
...
```

## Usage

```ruby
require 'lupina'

result = Lupina.generate_edc(
  capacity_kwp: 100,
  yearly_surplus_kwh: 30_000,
  month: 7,
  year: 2026,
  consumption_pattern: :industrial_lunch_break,
  ean: "859182400110224391",
  seed: 42  # optional, for reproducibility
)

File.write("output.csv", result[:csv])
puts result[:stats]
# => { month: 7, year: 2026, days: 31, capacity_kwp: 100.0,
#      total_surplus_kwh: 4949.6, peak_surplus_kw: 66.5, ... }
```

## Consumption patterns

| Pattern | Description |
|---|---|
| `:minimal` | Near-zero local consumption, almost all production exported |
| `:afternoon_weekend` | High weekday morning load, surplus appears in afternoon and all day on weekends |
| `:industrial_lunch_break` | Machines run all day, surplus only during lunch break (12-13) and weekends |
| `:early_shift` | Production shift 6-14, surplus from afternoon onwards + full weekends |
| `:residential` | Low daytime (people at work), high evening consumption |
| `:flat` | Even consumption throughout the day |

## Parameters

| Parameter | Description |
|---|---|
| `capacity_kwp` | Peak capacity of the solar plant in kWp |
| `yearly_surplus_kwh` | Total energy exported to grid per year in kWh |
| `month` | Month to generate (1-12) |
| `year` | Year (default: current year) |
| `consumption_pattern` | One of the patterns above (default: `:afternoon_weekend`) |
| `ean` | EAN identifier for the metering point |
| `seed` | Random seed for reproducible output |

## Example descriptions

Each example shows a natural language description as it would come from a human, followed by the extracted parameters. There are two types:

- **Production (solar plant)** — always has capacity in **kWp** and yearly přetoky (surplus exported to grid) in **MWh**
- **Consumption (customer)** — always has yearly consumption in **MWh**

---

### 1. Barn rooftop, no one lives there
> **Production:** "15 kWp na stodole, nikdo tam nebydlí, přetoky 14 MWh ročně"

```ruby
Lupina.generate_edc(capacity_kwp: 15, yearly_surplus_kwh: 14_000, consumption_pattern: :minimal, month: 7)
```

### 2. Factory with lunch break
> **Production:** "100 kWp, přetoky 30 MWh za rok, přes týden vše sežereme, max polední pauza když kluci vypnou mašiny"

```ruby
Lupina.generate_edc(capacity_kwp: 100, yearly_surplus_kwh: 30_000, consumption_pattern: :industrial_lunch_break, month: 7)
```

### 3. Workshop with early morning shift
> **Production:** "100 kWp, přetoky 50 MWh za rok, výroba jede od 6 do 14, víkend plné přetoky"

```ruby
Lupina.generate_edc(capacity_kwp: 100, yearly_surplus_kwh: 50_000, consumption_pattern: :early_shift, month: 8)
```

### 4. Solar farm on a meadow
> **Production:** "250 kWp na louce, jen trafostanice žere něco, přetoky 230 MWh ročně"

```ruby
Lupina.generate_edc(capacity_kwp: 250, yearly_surplus_kwh: 230_000, consumption_pattern: :minimal, month: 6)
```

### 5. Office building rooftop
> **Production:** "50 kWp na střeše kanceláří, přetoky hlavně odpoledne a celý víkend, 20 MWh za rok"

```ruby
Lupina.generate_edc(capacity_kwp: 50, yearly_surplus_kwh: 20_000, consumption_pattern: :afternoon_weekend, month: 5)
```

### 6. Family house, everyone at work during the day
> **Consumption:** "rodinný dům, 4 MWh ročně, lidi v práci přes den, spotřeba hlavně večer a ráno"

```ruby
# TODO: consumption EDC generation
# yearly_consumption_kwh: 4_000, pattern: :residential
```

### 7. Small bakery, early morning operation
> **Consumption:** "pekárna, spotřeba 25 MWh ročně, jedou od 3 do 11 ráno, pak zavřeno"

```ruby
# TODO: consumption EDC generation
# yearly_consumption_kwh: 25_000, pattern: :early_shift
```

### 8. Apartment building common areas
> **Consumption:** "bytovka, 8 MWh ročně, výtahy a osvětlení, celkem rovnoměrná spotřeba"

```ruby
# TODO: consumption EDC generation
# yearly_consumption_kwh: 8_000, pattern: :flat
```

### 9. Welding shop, weekday operation
> **Consumption:** "zámečnická dílna, spotřeba 60 MWh ročně, svářečky a kompresory jedou 7-17, víkend zavřeno"

```ruby
# TODO: consumption EDC generation
# yearly_consumption_kwh: 60_000, pattern: :early_shift
```

### 10. Cow barn with morning milking
> **Consumption:** "kravín, spotřeba 40 MWh za rok, dojení a krmení 4-10h, pak jen chlazení mléka"

```ruby
# TODO: consumption EDC generation
# yearly_consumption_kwh: 40_000, pattern: :early_shift
```

## Solar model

The generator uses a parametric model for Czech Republic (50°N):

- **Seasonal distribution** — monthly production shares from January (2.5%) to June (14%) peak
- **Daily curve** — sine-based solar profile between sunrise/sunset (with DST)
- **Weather** — random daily weather type (clear/partly/overcast) with seasonal probabilities
- **Noise** — ±15% intra-day cloud variation on both production and consumption
- **Calibration** — binary search scales consumption so monthly surplus matches the yearly target

Typical specific yield: ~1000 kWh/kWp/year.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt.

```ruby
# In bin/console:
result = Lupina.generate_edc(capacity_kwp: 100, yearly_surplus_kwh: 30_000, month: 7, seed: 42)
puts result[:stats]
```

See `examples/` for more usage scripts.
