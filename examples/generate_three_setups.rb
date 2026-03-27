# frozen_string_literal: true

# Three setups:
# 1) 100kWp, minimal consumption, rest full export (~90MWh surplus)
# 2) 100kWp, 30MWh surplus, weekday machines eat everything, surplus only weekends + lunch break
# 3) 100kWp, 50MWh surplus, early shift 6-14, afternoon + weekend surplus

require "bundler/setup"
require "lupina"
require "fileutils"

output_dir = File.expand_path("../tmp", __dir__)
FileUtils.mkdir_p(output_dir)

full_day = Array.new(24, 1.0)
lunch_only_wd = Array.new(24) { |h| h == 12 ? 0.8 : 0.0 }
afternoon_wd = Array.new(24) { |h| h >= 14 && h <= 20 ? 1.0 : 0.0 }

setups = [
  {
    name: "1_minimal_consumption",
    label: "1) Minimal consumption, full export",
    capacity_kwp: 100,
    yearly_surplus_kwh: 90_000,
    surplus_profile: { workday: full_day, saturday: full_day, sunday: full_day }
  },
  {
    name: "2_industrial_lunch",
    label: "2) Industrial weekday, surplus weekends + lunch break",
    capacity_kwp: 100,
    yearly_surplus_kwh: 30_000,
    surplus_profile: { workday: lunch_only_wd, saturday: full_day, sunday: full_day }
  },
  {
    name: "3_early_shift",
    label: "3) Early shift 6-14, afternoon + weekend surplus",
    capacity_kwp: 100,
    yearly_surplus_kwh: 50_000,
    surplus_profile: { workday: afternoon_wd, saturday: full_day, sunday: full_day }
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
      surplus_profile: setup[:surplus_profile],
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
