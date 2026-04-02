# frozen_string_literal: true

# End-to-end verification: diverse production + consumption descriptions → LLM → EDC → analysis

require "bundler/setup"
require "dotenv/load"
require "lupina"

Lupina.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY")
end

examples = [
  # --- PRODUCTION ---
  { desc: "200 kWp na střeše supermarketu, přetoky 40 MWh ročně, spotřeba hlavně chlaďáky a klimatizace celý den, víkend zavírají v 13h",
    type: "production", capacity: 200, yearly: 40_000,
    expect: "workday: low export (supermarket eats most), weekend afternoon: full export after 13h" },

  { desc: "30 kWp na garáži, nikdo tam nebydlí, jen nabíječka na elektroauto občas, přetoky 27 MWh",
    type: "production", capacity: 30, yearly: 27_000,
    expect: "high export ratio (90%), nearly full export all day" },

  { desc: "80 kWp na pile, přetoky 15 MWh za rok, katry a frézy jedou 6-16 pondělí až sobota dopoledne, neděle klid",
    type: "production", capacity: 80, yearly: 15_000,
    expect: "very low export ratio (19%), workday export only after 16h, saturday after noon, sunday full" },

  { desc: "45 kWp na střeše autoservisu, přetoky 25 MWh, dílna jede 7-16 Po-Pá, víkend zavřeno",
    type: "production", capacity: 45, yearly: 25_000,
    expect: "medium export ratio (56%), workday export from 16h, full weekends" },

  { desc: "150 kWp na střeše školy, přetoky 100 MWh, v létě prázdniny = plné přetoky, jinak spotřeba 8-15",
    type: "production", capacity: 150, yearly: 100_000,
    expect: "high ratio (67%), workday export after 15h + weekends, summer months much higher" },

  # --- CONSUMPTION ---
  { desc: "serverovna, spotřeba 120 MWh ročně, konstantní odběr 24/7 celý rok",
    type: "consumption", yearly: 120_000,
    expect: "flat profile ~1.0 all hours, all days" },

  { desc: "restaurace, spotřeba 35 MWh za rok, vaří od 9 do 22, neděle zavřeno, pondělí taky",
    type: "consumption", yearly: 35_000,
    expect: "workday 9-22 high (except Mon), sunday/monday zero, saturday full" },

  { desc: "fitness centrum, 50 MWh ročně, ráno 6-9 a večer 16-22 špička, přes den míň, víkend celý den",
    type: "consumption", yearly: 50_000,
    expect: "workday bimodal (6-9 + 16-22), weekend spread, never zero (lights/HVAC)" },

  { desc: "noční pekárna, spotřeba 30 MWh ročně, pece jedou od 22 do 6 ráno, přes den jen expedice a myčka",
    type: "consumption", yearly: 30_000,
    expect: "night peak 22-06, low daytime, 7 days a week" },

  { desc: "malý obchod, 8 MWh za rok, otevřeno Po-So 8-18, neděle zavřeno",
    type: "consumption", yearly: 8_000,
    expect: "workday+saturday 8-18, sunday standby only" },
]

errors = []

examples.each_with_index do |ex, idx|
  puts "=" * 70
  puts "#{idx + 1}) [#{ex[:type].upcase}] #{ex[:desc][0..80]}"
  puts "   Expected: #{ex[:expect]}"
  puts

  begin
    result = Lupina.from_description(ex[:desc], month: 7, year: 2026, seed: 42)
  rescue => e
    puts "   ERROR: #{e.message}"
    errors << "#{idx + 1}: #{e.message}"
    sleep 2
    next
  end

  params = result[:parsed]
  puts "   LLM type: #{params['type']}"
  puts "   Reasoning: #{params['reasoning']}"

  # Check type
  if params["type"] != ex[:type]
    errors << "#{idx + 1}: type mismatch (got #{params['type']}, expected #{ex[:type]})"
    puts "   TYPE MISMATCH!"
  end

  # Check numbers
  if ex[:type] == "production"
    puts "   Capacity: #{params['capacity_kwp']} kWp (expected #{ex[:capacity]})"
    puts "   Yearly export: #{params['yearly_surplus_kwh']} kWh (expected #{ex[:yearly]})"
    if params["capacity_kwp"] != ex[:capacity].to_f
      errors << "#{idx + 1}: capacity #{params['capacity_kwp']} != #{ex[:capacity]}"
    end
    if params["yearly_surplus_kwh"] != ex[:yearly].to_f
      errors << "#{idx + 1}: yearly export #{params['yearly_surplus_kwh']} != #{ex[:yearly]}"
    end
    ratio = ex[:yearly].to_f / (ex[:capacity] * 1000)
    puts "   Export ratio: #{(ratio * 100).round(0)}%"
    puts "   July export: #{result[:stats][:total_surplus_kwh]} kWh"
    puts "   July production: #{result[:stats][:total_production_kwh]} kWh"
  else
    puts "   Yearly consumption: #{params['yearly_consumption_kwh']} kWh (expected #{ex[:yearly]})"
    if params["yearly_consumption_kwh"] != ex[:yearly].to_f
      errors << "#{idx + 1}: yearly consumption #{params['yearly_consumption_kwh']} != #{ex[:yearly]}"
    end
    puts "   July consumption: #{result[:stats][:total_consumption_kwh]} kWh"
    puts "   July peak: #{result[:stats][:peak_consumption_kw]} kW"
  end

  # Show profiles (Monday as workday representative)
  mo = params["monday_profile"]
  sa = params["saturday_profile"]
  su = params["sunday_profile"]
  puts
  puts "   Hour  Monday                   Saturday                 Sunday"
  24.times do |h|
    printf "   %02d:00 %4.2f %-24s  %4.2f %-24s  %4.2f %s\n",
      h,
      mo[h], "#" * (mo[h] * 20).round,
      sa[h], "#" * (sa[h] * 20).round,
      su[h], "#" * (su[h] * 20).round
  end

  # For production: show hourly export distribution
  if ex[:type] == "production"
    lines = result[:csv].split("\n")[1..]
    dates = lines.map { |l| l.split(";")[0] }.uniq

    wd_hourly = Array.new(24, 0.0)
    wd_count = 0
    we_hourly = Array.new(24, 0.0)
    we_count = 0

    dates.each do |date_str|
      d = Date.strptime(date_str, "%d.%m.%Y")
      day_lines = lines.select { |l| l.start_with?(date_str) }
      is_weekend = d.saturday? || d.sunday?
      24.times do |h|
        total = day_lines.select { |l| l.split(";")[1].split(":")[0].to_i == h }
          .sum { |l| l.split(";")[3].tr(",", ".").to_f }
        if is_weekend
          we_hourly[h] += total
        else
          wd_hourly[h] += total
        end
      end
      is_weekend ? we_count += 1 : wd_count += 1
    end

    wd_hourly.map! { |v| wd_count > 0 ? v / wd_count : 0 }
    we_hourly.map! { |v| we_count > 0 ? v / we_count : 0 }

    puts
    puts "   Avg hourly EXPORT (kWh/day):"
    max_val = [wd_hourly.max, we_hourly.max].max
    scale = max_val > 0 ? 25.0 / max_val : 1
    (5..21).each do |h|
      printf "   %02d:00 %6.1f %-27s  %6.1f %s\n",
        h, wd_hourly[h], "#" * (wd_hourly[h] * scale).round,
        we_hourly[h], "#" * (we_hourly[h] * scale).round
    end
  end

  # For consumption: show hourly consumption distribution
  if ex[:type] == "consumption"
    lines = result[:csv].split("\n")[1..]
    dates = lines.map { |l| l.split(";")[0] }.uniq

    wd_hourly = Array.new(24, 0.0)
    wd_count = 0
    sa_hourly = Array.new(24, 0.0)
    sa_count = 0
    su_hourly = Array.new(24, 0.0)
    su_count = 0

    dates.each do |date_str|
      d = Date.strptime(date_str, "%d.%m.%Y")
      day_lines = lines.select { |l| l.start_with?(date_str) }
      24.times do |h|
        total = day_lines.select { |l| l.split(";")[1].split(":")[0].to_i == h }
          .sum { |l| l.split(";")[3].tr(",", ".").to_f }
        if d.sunday?
          su_hourly[h] += total
          su_count += 1 if h == 0
        elsif d.saturday?
          sa_hourly[h] += total
          sa_count += 1 if h == 0
        else
          wd_hourly[h] += total
          wd_count += 1 if h == 0
        end
      end
    end

    wd_hourly.map! { |v| wd_count > 0 ? v / wd_count : 0 }
    sa_hourly.map! { |v| sa_count > 0 ? v / sa_count : 0 }
    su_hourly.map! { |v| su_count > 0 ? v / su_count : 0 }

    puts
    puts "   Avg hourly CONSUMPTION (kWh/day):"
    max_val = [wd_hourly.max, sa_hourly.max, su_hourly.max].max
    scale = max_val > 0 ? 20.0 / max_val : 1
    puts "   Hour  Workday                  Saturday                 Sunday"
    24.times do |h|
      printf "   %02d:00 %5.1f %-22s  %5.1f %-22s  %5.1f %s\n",
        h, wd_hourly[h], "#" * (wd_hourly[h] * scale).round,
        sa_hourly[h], "#" * (sa_hourly[h] * scale).round,
        su_hourly[h], "#" * (su_hourly[h] * scale).round
    end
  end

  # Yearly total check
  yearly = (1..12).sum do |m|
    r = Lupina.from_description(ex[:desc], month: m, year: 2026, seed: 42)
    if ex[:type] == "production"
      r[:stats][:total_surplus_kwh]
    else
      r[:stats][:total_consumption_kwh]
    end
  end
  diff = (yearly - ex[:yearly]).abs
  puts
  puts "   Yearly total: #{yearly.round(0)} kWh (target: #{ex[:yearly]}, diff: #{diff.round(0)})"
  if diff > 200
    errors << "#{idx + 1}: yearly total off by #{diff.round(0)} kWh"
  end

  puts
  sleep 2
end

puts "=" * 70
if errors.empty?
  puts "ALL CHECKS PASSED"
else
  puts "ISSUES (#{errors.size}):"
  errors.each { |e| puts "  - #{e}" }
end
