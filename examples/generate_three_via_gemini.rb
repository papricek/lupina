# frozen_string_literal: true

# Three setups via Gemini — natural language in, EDC files out

require "bundler/setup"
require "dotenv/load"
require "lupina"
require "fileutils"

Lupina.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY")
end

output_dir = File.expand_path("../tmp", __dir__)
FileUtils.mkdir_p(output_dir)

setups = [
  { name: "1_minimal",
    desc: "100 kWp, místní spotřeba jen 10 MWh za rok, zbytek plné přetoky do sítě, malá místní spotřeba rovnoměrně" },
  { name: "2_industrial_lunch",
    desc: "100 kWp, přetoky 30 MWh do sítě za rok, přetoky pouze víkendy, přes týden vše sežereme, max polední pauza když kluci vypnou mašiny" },
  { name: "3_early_shift",
    desc: "100 kWp, přetoky 50 MWh za rok, jedem každý den něco přes den, ale jede výroba od 6 do 14 hodin, víkend plné přetoky" }
]

months = [ 2, 7 ]

setups.each do |setup|
  puts "=== #{setup[:desc][0..80]}... ==="

  params = Lupina.parse_description(setup[:desc])
  puts "  Gemini: #{params['reasoning']}"
  puts

  profile = {
    workday: params["workday_profile"],
    saturday: params["saturday_profile"],
    sunday: params["sunday_profile"]
  }

  # Show profiles
  wd = params["workday_profile"]
  sa = params["saturday_profile"]
  su = params["sunday_profile"]
  puts "  Hour  Mo-Fr                    Saturday                 Sunday"
  24.times do |h|
    printf "  %02d:00 %4.2f %-24s  %4.2f %-24s  %4.2f %s\n",
      h,
      wd[h], "#" * (wd[h] * 20).round,
      sa[h], "#" * (sa[h] * 20).round,
      su[h], "#" * (su[h] * 20).round
  end
  puts

  months.each do |month|
    result = Lupina.generate_edc(
      capacity_kwp: params["capacity_kwp"],
      yearly_surplus_kwh: params["yearly_surplus_kwh"],
      month: month, year: 2026,
      surplus_profile: profile,
      seed: 42
    )

    filename = "edc_#{setup[:name]}_#{month.to_s.rjust(2, '0')}_2026.csv"
    path = File.join(output_dir, filename)
    File.write(path, result[:csv])

    # Verify sum
    raw_sum = result[:csv].split("\n")[1..].sum { |l| l.split(";")[3].tr(",", ".").to_f }
    puts "  #{Date::MONTHNAMES[month]}: #{result[:stats][:total_surplus_kwh]} kWh (sum=#{raw_sum.round(1)}) -> #{filename}"
  end
  puts
  sleep 2
end
