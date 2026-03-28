# frozen_string_literal: true

# Generate EDC files for all 10 test scenarios (5 production + 5 consumption)
# Generates July 2026 for each.

require "bundler/setup"
require "dotenv/load"
require "lupina"
require "fileutils"

Lupina.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY")
end

output_dir = File.expand_path("../tmp/scenarios", __dir__)
FileUtils.mkdir_p(output_dir)

scenarios = [
  # Production
  { id: "P1", name: "supermarket",
    desc: "200 kWp na střeše supermarketu, přetoky 40 MWh ročně, spotřeba hlavně chlaďáky a klimatizace celý den, víkend zavírají v 13h" },
  { id: "P2", name: "garaz",
    desc: "30 kWp na garáži, nikdo tam nebydlí, jen nabíječka na elektroauto občas, přetoky 27 MWh" },
  { id: "P3", name: "pila",
    desc: "80 kWp na pile, přetoky 15 MWh za rok, katry a frézy jedou 6-16 pondělí až sobota dopoledne, neděle klid" },
  { id: "P4", name: "autoservis",
    desc: "45 kWp na střeše autoservisu, přetoky 25 MWh, dílna jede 7-16 Po-Pá, víkend zavřeno" },
  { id: "P5", name: "skola",
    desc: "150 kWp na střeše školy, přetoky 100 MWh, v létě prázdniny = plné přetoky, jinak spotřeba 8-15" },

  # Consumption
  { id: "C1", name: "serverovna",
    desc: "serverovna, spotřeba 120 MWh ročně, konstantní odběr 24/7 celý rok" },
  { id: "C2", name: "restaurace",
    desc: "restaurace, spotřeba 35 MWh za rok, vaří od 9 do 22, neděle zavřeno, pondělí taky" },
  { id: "C3", name: "fitness",
    desc: "fitness centrum, 50 MWh ročně, ráno 6-9 a večer 16-22 špička, přes den míň, víkend celý den" },
  { id: "C4", name: "nocni_pekarna",
    desc: "noční pekárna, spotřeba 30 MWh ročně, pece jedou od 22 do 6 ráno, přes den jen expedice a myčka" },
  { id: "C5", name: "obchod",
    desc: "malý obchod, 8 MWh za rok, otevřeno Po-So 8-18, neděle zavřeno" },
]

scenarios.each do |sc|
  puts "Generating #{sc[:id]} #{sc[:name]}..."

  result = Lupina.from_description(sc[:desc], month: 7, year: 2026, seed: 42)
  params = result[:parsed]

  filename = "#{sc[:id]}_#{sc[:name]}_07_2026.csv"
  path = File.join(output_dir, filename)
  File.write(path, result[:csv])

  if params["type"] == "production"
    printf "  %s: export=%s kWh, production=%s kWh -> %s\n",
      sc[:id], result[:stats][:total_surplus_kwh], result[:stats][:total_production_kwh], filename
  else
    printf "  %s: consumption=%s kWh, peak=%s kW -> %s\n",
      sc[:id], result[:stats][:total_consumption_kwh], result[:stats][:peak_consumption_kw], filename
  end

  sleep 2
end

puts "Done! Files in #{output_dir}"
