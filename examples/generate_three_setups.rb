# frozen_string_literal: true

# Three setups:
# 1) 100kWp, 10MWh local consumption, rest full export (~90MWh surplus)
# 2) 100kWp, 30MWh surplus, weekday machines eat everything, surplus only weekends + lunch break
# 3) 100kWp, 50MWh surplus, early shift 6-14, afternoon + weekend surplus

require "bundler/setup"
require "lupina"
require "fileutils"

output_dir = File.expand_path("../tmp", __dir__)
FileUtils.mkdir_p(output_dir)

setups = [
  {
    name: "1_minimal_consumption",
    label: "1) Minimal consumption, full export",
    capacity_kwp: 100,
    yearly_surplus_kwh: 90_000,
    consumption_pattern: :minimal
  },
  {
    name: "2_industrial_lunch",
    label: "2) Industrial weekday, surplus weekends + lunch break",
    capacity_kwp: 100,
    yearly_surplus_kwh: 30_000,
    consumption_pattern: :industrial_lunch_break
  },
  {
    name: "3_early_shift",
    label: "3) Early shift 6-14, afternoon + weekend surplus",
    capacity_kwp: 100,
    yearly_surplus_kwh: 50_000,
    consumption_pattern: :early_shift
  }
]

months = [ 2, 7 ]

setups.each do |setup|
  months.each do |month|
    result = Lupina.generate_edc(
      capacity_kwp: setup[:capacity_kwp],
      yearly_surplus_kwh: setup[:yearly_surplus_kwh],
      month: month,
      year: 2026,
      consumption_pattern: setup[:consumption_pattern],
      ean: "859182400110224391",
      seed: 42
    )

    filename = "edc_#{setup[:name]}_#{month.to_s.rjust(2, '0')}_2026.csv"
    path = File.join(output_dir, filename)
    File.write(path, result[:csv])

    s = result[:stats]
    puts "=== #{setup[:label]} — #{Date::MONTHNAMES[month]} ==="
    puts "  Surplus: #{s[:total_surplus_kwh]} kWh  (peak #{s[:peak_surplus_kw]} kW)"
    puts "  -> #{path}"
    puts
  end
end
