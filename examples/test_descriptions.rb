# frozen_string_literal: true

# Test all 10 README descriptions through Gemini parser

require "bundler/setup"
require "dotenv/load"
require "lupina"
require "json"

Lupina.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY")
end

descriptions = [
  # Production examples
  { input: "15 kWp na stodole, nikdo tam nebydlí, přetoky 14 MWh ročně",
    expected: { type: "production", capacity_kwp: 15, yearly_surplus_kwh: 14_000 } },

  { input: "100 kWp, přetoky 30 MWh za rok, přes týden vše sežereme, max polední pauza když kluci vypnou mašiny",
    expected: { type: "production", capacity_kwp: 100, yearly_surplus_kwh: 30_000 } },

  { input: "100 kWp, přetoky 50 MWh za rok, výroba jede od 6 do 14, víkend plné přetoky",
    expected: { type: "production", capacity_kwp: 100, yearly_surplus_kwh: 50_000 } },

  { input: "250 kWp na louce, jen trafostanice žere něco, přetoky 230 MWh ročně",
    expected: { type: "production", capacity_kwp: 250, yearly_surplus_kwh: 230_000 } },

  { input: "50 kWp na střeše kanceláří, přetoky hlavně odpoledne a celý víkend, 20 MWh za rok",
    expected: { type: "production", capacity_kwp: 50, yearly_surplus_kwh: 20_000 } },

  # Consumption examples
  { input: "rodinný dům, 4 MWh ročně, lidi v práci přes den, spotřeba hlavně večer a ráno",
    expected: { type: "consumption", yearly_consumption_kwh: 4_000 } },

  { input: "pekárna, spotřeba 25 MWh ročně, jedou od 3 do 11 ráno, pak zavřeno",
    expected: { type: "consumption", yearly_consumption_kwh: 25_000 } },

  { input: "bytovka, 8 MWh ročně, výtahy a osvětlení, celkem rovnoměrná spotřeba",
    expected: { type: "consumption", yearly_consumption_kwh: 8_000 } },

  { input: "zámečnická dílna, spotřeba 60 MWh ročně, svářečky a kompresory jedou 7-17, víkend zavřeno",
    expected: { type: "consumption", yearly_consumption_kwh: 60_000 } },

  { input: "kravín, spotřeba 40 MWh za rok, dojení a krmení 4-10h, pak jen chlazení mléka",
    expected: { type: "consumption", yearly_consumption_kwh: 40_000 } }
]

puts "Testing #{descriptions.size} descriptions through Gemini...\n\n"

pass = 0
fail_list = []

descriptions.each_with_index do |desc, i|
  print "#{i + 1}/#{descriptions.size} "
  begin
    result = Lupina.parse_description(desc[:input])
    exp = desc[:expected]

    issues = []

    # Check type
    issues << "type: got #{result['type']}, expected #{exp[:type]}" if result["type"] != exp[:type]

    # Check numbers
    if exp[:type] == "production"
      if result["capacity_kwp"] != exp[:capacity_kwp]
        issues << "capacity: got #{result['capacity_kwp']}, expected #{exp[:capacity_kwp]}"
      end
      if result["yearly_surplus_kwh"] != exp[:yearly_surplus_kwh]
        issues << "surplus: got #{result['yearly_surplus_kwh']}, expected #{exp[:yearly_surplus_kwh]}"
      end
    else
      if result["yearly_consumption_kwh"] != exp[:yearly_consumption_kwh]
        issues << "consumption: got #{result['yearly_consumption_kwh']}, expected #{exp[:yearly_consumption_kwh]}"
      end
    end

    # Check profiles exist and have correct size
    %w[workday_profile saturday_profile sunday_profile].each do |key|
      unless result[key].is_a?(Array) && result[key].size == 24
        issues << "#{key}: missing or wrong size"
      end
    end

    if issues.empty?
      puts "PASS  #{desc[:input][0..60]}"
      pass += 1
    else
      puts "FAIL  #{desc[:input][0..60]}"
      issues.each { |issue| puts "       #{issue}" }
      puts "       reasoning: #{result['reasoning']}"
      fail_list << { index: i + 1, input: desc[:input], issues: issues, reasoning: result["reasoning"] }
    end

    # Generate CSV for production examples to verify end-to-end
    if result["type"] == "production"
      profile = {
        workday: result["workday_profile"],
        saturday: result["saturday_profile"],
        sunday: result["sunday_profile"]
      }
      edc = Lupina.generate_edc(
        capacity_kwp: result["capacity_kwp"],
        yearly_surplus_kwh: result["yearly_surplus_kwh"],
        month: 7, year: 2026,
        surplus_profile: profile,
        seed: 42
      )
      printf "       -> July: %s kWh surplus\n", edc[:stats][:total_surplus_kwh]
    end

  rescue => e
    puts "ERROR #{desc[:input][0..60]}"
    puts "       #{e.class}: #{e.message}"
    fail_list << { index: i + 1, input: desc[:input], issues: [ e.message ] }
  end

  sleep 1 # rate limiting
end

puts "\n#{'=' * 60}"
puts "#{pass}/#{descriptions.size} passed"
if fail_list.any?
  puts "\nFailed:"
  fail_list.each { |f| puts "  #{f[:index]}) #{f[:issues].join(', ')}" }
end
