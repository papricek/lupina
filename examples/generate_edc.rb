# frozen_string_literal: true

# Generates a sample EDC production file based on:
# "100kWp, přetoky 30MWh za rok, hlavně odpoledne a o víkendu, nejvíc v létě"

require "bundler/setup"
require "lupina"
require "fileutils"

output_dir = File.expand_path("../tmp", __dir__)
FileUtils.mkdir_p(output_dir)

months = [ 2, 7 ]

months.each do |month|
  result = Lupina.generate_edc(
    capacity_kwp: 100,
    yearly_surplus_kwh: 30_000,
    month: month,
    year: 2026,
    consumption_pattern: :afternoon_weekend,
    ean: "859182400110224391",
    seed: 42
  )

  filename = "edc_100kwp_#{month.to_s.rjust(2, '0')}_2026.csv"
  path = File.join(output_dir, filename)
  File.write(path, result[:csv])

  s = result[:stats]
  puts "=== #{Date::MONTHNAMES[month]} #{s[:year]} (#{s[:days]} days) ==="
  puts "  Capacity:       #{s[:capacity_kwp]} kWp"
  puts "  Surplus (IN/OUT): #{s[:total_surplus_kwh]} kWh"
  puts "  Peak surplus:   #{s[:peak_surplus_kw]} kW"
  puts "  -> #{path}"
  puts
end
