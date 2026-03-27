# frozen_string_literal: true

# Test all 5 production examples from README

require "bundler/setup"
require "lupina"

examples = [
  {
    name: "1_barn_rooftop",
    label: "1) 15 kWp barn, 14 MWh surplus, minimal consumption",
    capacity_kwp: 15, yearly_surplus_kwh: 14_000, consumption_pattern: :minimal
  },
  {
    name: "2_factory_lunch",
    label: "2) 100 kWp factory, 30 MWh surplus, lunch break only",
    capacity_kwp: 100, yearly_surplus_kwh: 30_000, consumption_pattern: :industrial_lunch_break
  },
  {
    name: "3_workshop_early",
    label: "3) 100 kWp workshop, 50 MWh surplus, early shift 6-14",
    capacity_kwp: 100, yearly_surplus_kwh: 50_000, consumption_pattern: :early_shift
  },
  {
    name: "4_solar_farm",
    label: "4) 250 kWp solar farm, 230 MWh surplus, minimal load",
    capacity_kwp: 250, yearly_surplus_kwh: 230_000, consumption_pattern: :minimal
  },
  {
    name: "5_office_rooftop",
    label: "5) 50 kWp office, 20 MWh surplus, afternoon+weekend",
    capacity_kwp: 50, yearly_surplus_kwh: 20_000, consumption_pattern: :afternoon_weekend
  }
]

errors = []

examples.each do |ex|
  puts "=== #{ex[:label]} ==="

  # Yearly totals
  yearly_surplus = 0.0
  yearly_production = 0.0
  (1..12).each do |m|
    r = Lupina.generate_edc(
      capacity_kwp: ex[:capacity_kwp], yearly_surplus_kwh: ex[:yearly_surplus_kwh],
      month: m, year: 2026, consumption_pattern: ex[:consumption_pattern], seed: 42
    )
    yearly_surplus += r[:stats][:total_surplus_kwh]
    yearly_production += r[:stats][:total_production_kwh]
  end

  surplus_diff = (yearly_surplus - ex[:yearly_surplus_kwh]).abs
  expected_prod = ex[:capacity_kwp] * 1000
  prod_diff = (yearly_production - expected_prod).abs

  printf "  Yearly production: %8.0f kWh (expected %d, diff %.0f)\n", yearly_production, expected_prod, prod_diff
  printf "  Yearly surplus:    %8.0f kWh (expected %d, diff %.0f)\n", yearly_surplus, ex[:yearly_surplus_kwh], surplus_diff

  if surplus_diff > 100
    errors << "#{ex[:name]}: surplus off by #{surplus_diff.round(0)} kWh"
  end
  if yearly_surplus > yearly_production
    errors << "#{ex[:name]}: surplus (#{yearly_surplus.round(0)}) > production (#{yearly_production.round(0)})"
  end

  # Spot-check July file
  r = Lupina.generate_edc(
    capacity_kwp: ex[:capacity_kwp], yearly_surplus_kwh: ex[:yearly_surplus_kwh],
    month: 7, year: 2026, consumption_pattern: ex[:consumption_pattern], seed: 42
  )
  csv = r[:csv]
  lines = csv.split("\n")
  header = lines[0]
  data_lines = lines[1..]

  # Check header format
  unless header.match?(/\ADatum;Cas od;Cas do;IN-\d+-D;OUT-\d+-D\z/)
    errors << "#{ex[:name]}: bad header format"
  end

  # Check row count (31 days * 96 intervals)
  unless data_lines.size == 31 * 96
    errors << "#{ex[:name]}: July has #{data_lines.size} rows, expected #{31 * 96}"
  end

  # Check IN == OUT in every row
  in_out_mismatch = data_lines.count do |l|
    parts = l.split(";")
    parts[3] != parts[4]
  end
  if in_out_mismatch > 0
    errors << "#{ex[:name]}: #{in_out_mismatch} rows where IN != OUT"
  end

  # Check night = 0
  night_nonzero = data_lines.count do |l|
    parts = l.split(";")
    hour = parts[1].split(":")[0].to_i
    val = parts[3].tr(",", ".").to_f
    (hour >= 22 || hour < 4) && val > 0
  end
  if night_nonzero > 0
    errors << "#{ex[:name]}: #{night_nonzero} night intervals (22-04) with non-zero surplus"
  end

  # Check no negative values
  negatives = data_lines.count do |l|
    parts = l.split(";")
    parts[3].tr(",", ".").to_f < 0 || parts[4].tr(",", ".").to_f < 0
  end
  if negatives > 0
    errors << "#{ex[:name]}: #{negatives} negative values"
  end

  # Check trailing semicolon
  bad_format = data_lines.count { |l| !l.end_with?(";") }
  if bad_format > 0
    errors << "#{ex[:name]}: #{bad_format} rows missing trailing semicolon"
  end

  # Raw sum check
  raw_sum = data_lines.sum { |l| l.split(";")[3].tr(",", ".").to_f }
  printf "  July IN sum:       %8.1f kWh (stats: #{r[:stats][:total_surplus_kwh]})\n", raw_sum

  puts
end

if errors.empty?
  puts "ALL CHECKS PASSED"
else
  puts "ERRORS:"
  errors.each { |e| puts "  - #{e}" }
end
