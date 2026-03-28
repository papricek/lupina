# frozen_string_literal: true

# End-to-end verification: README descriptions → LLM → EDC → analysis
# Tests that generated data is physically plausible and matches the description intent.

require "bundler/setup"
require "dotenv/load"
require "lupina"

Lupina.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY")
end

descriptions = [
  { name: "1_barn",
    desc: "15 kWp na stodole, nikdo tam nebydlí, přetoky 14 MWh ročně",
    capacity: 15, surplus: 14_000,
    expect: "surplus all day (no local consumption)" },

  { name: "2_factory_lunch",
    desc: "100 kWp, přetoky 30 MWh za rok, přes týden vše sežereme, max polední pauza když kluci vypnou mašiny",
    capacity: 100, surplus: 30_000,
    expect: "workday surplus mainly around lunch, full weekend surplus" },

  { name: "3_early_shift",
    desc: "100 kWp, přetoky 50 MWh za rok, výroba jede od 6 do 14, víkend plné přetoky",
    capacity: 100, surplus: 50_000,
    expect: "workday surplus from ~14:00 onwards, full weekend surplus" },

  { name: "4_solar_farm",
    desc: "250 kWp na louce, jen trafostanice žere něco, přetoky 230 MWh ročně",
    capacity: 250, surplus: 230_000,
    expect: "surplus all day every day (minimal consumption)" },

  { name: "5_office",
    desc: "50 kWp na střeše kanceláří, přetoky hlavně odpoledne a celý víkend, 20 MWh za rok",
    capacity: 50, surplus: 20_000,
    expect: "workday surplus mainly afternoon, full weekend surplus" }
]

errors = []

descriptions.each_with_index do |ex, idx|
  puts "=" * 70
  puts "#{idx + 1}) #{ex[:desc]}"
  puts "   Expected: #{ex[:expect]}"
  puts

  # Parse via LLM
  begin
    params = Lupina.parse_description(ex[:desc])
  rescue => e
    puts "   ERROR parsing: #{e.message}"
    errors << "#{ex[:name]}: parse failed"
    next
  end

  puts "   LLM reasoning: #{params['reasoning']}"
  puts "   Type: #{params['type']}, capacity: #{params['capacity_kwp']} kWp, surplus: #{params['yearly_surplus_kwh']} kWh"

  # Check extracted numbers
  if params["capacity_kwp"] != ex[:capacity]
    puts "   WARN: capacity mismatch (got #{params['capacity_kwp']}, expected #{ex[:capacity]})"
    errors << "#{ex[:name]}: capacity #{params['capacity_kwp']} != #{ex[:capacity]}"
  end
  if params["yearly_surplus_kwh"] != ex[:surplus]
    puts "   WARN: surplus mismatch (got #{params['yearly_surplus_kwh']}, expected #{ex[:surplus]})"
    errors << "#{ex[:name]}: surplus #{params['yearly_surplus_kwh']} != #{ex[:surplus]}"
  end

  # Show surplus profiles
  wd = params["workday_profile"]
  sa = params["saturday_profile"]
  su = params["sunday_profile"]
  puts
  puts "   Surplus profiles (LLM-generated):"
  puts "   Hour  Workday                  Saturday                 Sunday"
  24.times do |h|
    printf "   %02d:00 %4.2f %-24s  %4.2f %-24s  %4.2f %s\n",
      h,
      wd[h], "#" * (wd[h] * 20).round,
      sa[h], "#" * (sa[h] * 20).round,
      su[h], "#" * (su[h] * 20).round
  end

  profile = { workday: wd, saturday: sa, sunday: su }

  # Generate July and January
  [1, 7].each do |month|
    result = Lupina.generate_edc(
      capacity_kwp: params["capacity_kwp"],
      yearly_surplus_kwh: params["yearly_surplus_kwh"],
      month: month, year: 2026,
      surplus_profile: profile, seed: 42
    )

    lines = result[:csv].split("\n")[1..]
    dates = lines.map { |l| l.split(";")[0] }.uniq

    puts
    puts "   --- #{Date::MONTHNAMES[month]} 2026 ---"
    puts "   Total surplus: #{result[:stats][:total_surplus_kwh]} kWh"
    puts "   Total production: #{result[:stats][:total_production_kwh]} kWh"
    puts "   Peak surplus: #{result[:stats][:peak_surplus_kw]} kW"

    if result[:stats][:total_surplus_kwh] > result[:stats][:total_production_kwh]
      errors << "#{ex[:name]} #{Date::MONTHNAMES[month]}: surplus > production!"
    end

    # Analyze workday vs weekend pattern
    wd_hourly = Array.new(24, 0.0)
    wd_count = 0
    we_hourly = Array.new(24, 0.0)
    we_count = 0

    dates.each do |date_str|
      d = Date.strptime(date_str, "%d.%m.%Y")
      day_lines = lines.select { |l| l.start_with?(date_str) }
      is_weekend = d.saturday? || d.sunday?

      24.times do |h|
        hour_lines = day_lines.select { |l| l.split(";")[1].split(":")[0].to_i == h }
        total = hour_lines.sum { |l| l.split(";")[3].tr(",", ".").to_f }
        if is_weekend
          we_hourly[h] += total
        else
          wd_hourly[h] += total
        end
      end

      if is_weekend
        we_count += 1
      else
        wd_count += 1
      end

      # Check every day has SOME surplus during solar hours
      day_total = day_lines.sum { |l| l.split(";")[3].tr(",", ".").to_f }
      if day_total < 0.01
        errors << "#{ex[:name]} #{Date::MONTHNAMES[month]}: #{date_str} has ZERO surplus"
      end
    end

    # Average per day
    wd_hourly.map! { |v| wd_count > 0 ? v / wd_count : 0 }
    we_hourly.map! { |v| we_count > 0 ? v / we_count : 0 }

    puts
    puts "   Average hourly surplus (kWh per day):"
    puts "   Hour  Workday                          Weekend"
    max_val = [wd_hourly.max, we_hourly.max].max
    scale = max_val > 0 ? 30.0 / max_val : 1
    (5..21).each do |h|
      wd_bar = "#" * (wd_hourly[h] * scale).round
      we_bar = "#" * (we_hourly[h] * scale).round
      printf "   %02d:00 %6.1f %-32s  %6.1f %s\n", h, wd_hourly[h], wd_bar, we_hourly[h], we_bar
    end

    # Check night = 0
    night_total = lines.sum do |l|
      h = l.split(";")[1].split(":")[0].to_i
      val = l.split(";")[3].tr(",", ".").to_f
      (h >= 22 || h < 4) ? val : 0
    end
    if night_total > 0.01
      errors << "#{ex[:name]} #{Date::MONTHNAMES[month]}: night surplus #{night_total.round(2)} kWh"
    end
  end

  # Yearly total check
  yearly = (1..12).sum do |m|
    r = Lupina.generate_edc(
      capacity_kwp: params["capacity_kwp"],
      yearly_surplus_kwh: params["yearly_surplus_kwh"],
      month: m, year: 2026, surplus_profile: profile, seed: 42
    )
    r[:stats][:total_surplus_kwh]
  end
  diff = (yearly - params["yearly_surplus_kwh"]).abs
  puts
  puts "   Yearly surplus: #{yearly.round(0)} kWh (target: #{params['yearly_surplus_kwh'].round(0)}, diff: #{diff.round(0)})"
  if diff > 100
    errors << "#{ex[:name]}: yearly surplus off by #{diff.round(0)} kWh"
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
