# frozen_string_literal: true

# Test LLM-generated custom consumption profiles

require "bundler/setup"
require "dotenv/load"
require "lupina"

Lupina.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY")
end

descriptions = [
  "100 kWp, přetoky 30 MWh za rok, přes týden vše sežereme, max polední pauza když kluci vypnou mašiny",
  "100 kWp, přetoky 50 MWh za rok, výroba jede od 6 do 14, víkend plné přetoky",
  "60 kWp na kravíně, přetoky 35 MWh, ráno dojení 4-10h, pak jen chlazení mléka celý den",
  "15 kWp na stodole, nikdo tam nebydlí, přetoky 14 MWh ročně",
  "50 kWp na pekárně, přetoky 20 MWh, pečou od 3 do 11 ráno, odpoledne jen prodej"
]

descriptions.each_with_index do |desc, i|
  puts "=== #{i + 1}) #{desc[0..70]}... ==="

  result = Lupina.from_description(desc, month: 7, year: 2026, seed: 42)
  params = result[:parsed]

  puts "  Reasoning: #{params['reasoning']}"
  puts "  July surplus: #{result[:stats][:total_surplus_kwh]} kWh"
  puts

  # Visualize profiles
  wd = params["weekday_profile"]
  we = params["weekend_profile"]

  puts "  Hour  Weekday                  Weekend"
  24.times do |h|
    wd_bar = "#" * (wd[h] * 30).round
    we_bar = "#" * (we[h] * 30).round
    printf "  %02d:00 %4.2f %-30s  %4.2f %s\n", h, wd[h], wd_bar, we[h], we_bar
  end

  # Show a sample Wednesday
  csv_lines = result[:csv].split("\n")
  wed = csv_lines.select { |l| l.start_with?("01.07.2026") }
  puts
  puts "  Wed Jul 1 surplus:"
  wed.each_slice(4).with_index do |chunk, j|
    parts = chunk[0].split(";")
    v = parts[3].tr(",", ".").to_f
    next if j % 2 != 0
    bar = "|" * (v * 4).round
    printf "    %s-%s  %6s  %s\n", parts[1], parts[2], parts[3], bar
  end
  puts
  puts

  sleep 2
end
