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

## Example descriptions and how to map them

The idea is that a human writes a short description and you pick the right parameters. Here are 10 real-world examples:

### 1. Small rooftop, almost no self-consumption
> "15kWp na stodole, nikdo tam nebydlí, všechno jde do sítě"

```ruby
Lupina.generate_edc(capacity_kwp: 15, yearly_surplus_kwh: 14_000, consumption_pattern: :minimal, month: 7)
```

### 2. Family house with daytime jobs
> "10kWp na rodinném domě, přes den nikdo doma, přetoky tak 4MWh za rok"

```ruby
Lupina.generate_edc(capacity_kwp: 10, yearly_surplus_kwh: 4_000, consumption_pattern: :residential, month: 6)
```

### 3. Factory running two shifts, lunch break surplus
> "100kWp, 30MWh přetoky za rok, přes týden vše sežereme, max polední pauza když kluci vypnou mašiny"

```ruby
Lupina.generate_edc(capacity_kwp: 100, yearly_surplus_kwh: 30_000, consumption_pattern: :industrial_lunch_break, month: 7)
```

### 4. Workshop with early shift
> "100kWp, přetoky 50MWh za rok, výroba jede od 6 do 14, víkend plné přetoky"

```ruby
Lupina.generate_edc(capacity_kwp: 100, yearly_surplus_kwh: 50_000, consumption_pattern: :early_shift, month: 8)
```

### 5. Large solar farm, minimal on-site load
> "250kWp na louce, jen trafostanice žere něco, 230MWh přetoků ročně"

```ruby
Lupina.generate_edc(capacity_kwp: 250, yearly_surplus_kwh: 230_000, consumption_pattern: :minimal, month: 6)
```

### 6. Office building with weekend emptiness
> "50kWp na střeše kanceláří, přetoky hlavně odpoledne a celý víkend, asi 20MWh za rok"

```ruby
Lupina.generate_edc(capacity_kwp: 50, yearly_surplus_kwh: 20_000, consumption_pattern: :afternoon_weekend, month: 5)
```

### 7. Small workshop, everything consumed
> "30kWp, svářečky a kompresory jedou celý den, přetoky minimální, tak 2MWh za rok"

```ruby
Lupina.generate_edc(capacity_kwp: 30, yearly_surplus_kwh: 2_000, consumption_pattern: :industrial_lunch_break, month: 7)
```

### 8. Seasonal accommodation
> "20kWp na chatě, v létě tam někdo je ale hlavně večer, přetoky 8MWh ročně"

```ruby
Lupina.generate_edc(capacity_kwp: 20, yearly_surplus_kwh: 8_000, consumption_pattern: :residential, month: 7)
```

### 9. Agricultural building with morning milking
> "60kWp na kravíně, ráno dojení a krmení 4-10h, pak klid, přetoky 35MWh"

```ruby
Lupina.generate_edc(capacity_kwp: 60, yearly_surplus_kwh: 35_000, consumption_pattern: :early_shift, month: 6)
```

### 10. Winter month for a medium system
> "Chci vidět jak vypadá únor pro 80kWp s přetoky 40MWh ročně, normální kancelář"

```ruby
Lupina.generate_edc(capacity_kwp: 80, yearly_surplus_kwh: 40_000, consumption_pattern: :afternoon_weekend, month: 2)
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
