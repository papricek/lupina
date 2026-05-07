# frozen_string_literal: true

require "json"

module Lupina
  # Sister to HourlyProfileParser, but for CONSUMPTION (spotřeba) instead of
  # production (přetoky). The LLM produces 24 absolute kWh-per-hour values
  # for typical workday/weekend/holiday at the given customer in the given month.
  #
  # Differences from HourlyProfileParser:
  #   - No capacity_kwp parameter (consumption isn't bounded by panel capacity)
  #   - yearly_consumption_kwh instead of yearly_surplus_kwh
  #   - No solar curve assumption — shape comes entirely from description
  #   - Sector-aware shape priors (residential bimodal, industrial 24/7,
  #     office 8-17, restaurant evening, school weekday-only-with-summer-break)
  #   - Baseline (off-peak) is meaningful and emphasized
  #   - Customer overestimation discount NOT applied (consumers usually report
  #     accurately or under-report; verified empirically as part of autoresearch)
  class HourlyConsumptionParser
    RESPONSE_KEYS = %w[workday_kwh_per_hour weekend_kwh_per_hour].freeze

    def initialize(description:, yearly_consumption_kwh:, month:, year:, model:)
      @description = description.to_s.strip
      @yearly_consumption_kwh = yearly_consumption_kwh.to_f
      @month = month.to_i
      @year = year.to_i
      @model = model
    end

    def call
      chat = RubyLLM.chat(model: @model).with_temperature(0)
      response = chat.ask(prompt)
      parsed = JSON.parse(extract_json(response.content))
      validate!(parsed)
      normalize!(parsed)
      parsed
    rescue JSON::ParserError => e
      raise ExtractionError, "HourlyConsumptionParser: failed to parse LLM response as JSON: #{e.message}"
    end

    private

    MONTH_NAMES_CS = {
      1 => "leden", 2 => "únor", 3 => "březen", 4 => "duben",
      5 => "květen", 6 => "červen", 7 => "červenec", 8 => "srpen",
      9 => "září", 10 => "říjen", 11 => "listopad", 12 => "prosinec"
    }.freeze

    # Czech yearly→monthly consumption shares — heating-dominant in winter.
    # Sums to ~1.0. Used as fallback when no description anchors guide.
    MONTHLY_SHARE = {
      1 => 0.115, 2 => 0.105, 3 => 0.095, 4 => 0.075, 5 => 0.060, 6 => 0.055,
      7 => 0.055, 8 => 0.060, 9 => 0.075, 10 => 0.090, 11 => 0.105, 12 => 0.110
    }.freeze

    def prompt
      anchors = ConsumptionAnchorExtractor.call(@description)
      anchor_block = ConsumptionAnchorExtractor.format_for_prompt(anchors, target_month: @month)

      <<~PROMPT
        Jsi expert na české odběratele elektřiny a 15min EDC měření.
        Tvoje úloha: odhadnout PROFIL SPOTŘEBY pro jeden měsíc v ABSOLUTNÍCH KWH PER HODINU.

        VSTUPY:
        Měsíc: #{MONTH_NAMES_CS[@month]} #{@year} (číslo měsíce: #{@month})
        Roční spotřeba: #{@yearly_consumption_kwh.round(0)} kWh (= #{(@yearly_consumption_kwh / 1000.0).round(1)} MWh)

        #{anchor_block}Popis odběrného místa:
        "#{@description}"

        ÚKOL:
        Vrať dvě (volitelně tři) pole po 24 číslech (jedno číslo per hodinu, hodiny 0-23
        v MÍSTNÍM čase Europe/Prague):
        - "workday_kwh_per_hour": kolik kWh ODEBERE objekt v dané hodině typického všedního dne
        - "weekend_kwh_per_hour": totéž pro typický víkendový den
        - "holiday_kwh_per_hour": totéž pro státní svátek (volitelné, null = stejné jako víkend)
        + "expected_monthly_kwh": tvůj odhad měsíčního součtu

        ZÁSADNÍ PRINCIPY:

        1. Hodnoty jsou ABSOLUTNÍ kWh za jednu hodinu, NE relativní 0-1.
           Příklad rodinný dům 7 MWh/rok: noční baseline ~0.2 kWh/h, ranní špička 1.0 kWh/h v 7h,
           denní útlum 0.4 kWh/h, večerní špička 1.5 kWh/h v 19h.

        2. ŽÁDNÁ solární křivka. Spotřeba NENÍ řízena sluncem. Tvar přebírá ze sektoru:
           - **Domácnost / rodinný dům** (sector=residential): BIMODÁLNÍ profil — ranní špička
             6-8 h (snídaně, příprava do práce/školy), denní útlum 9-15 (lidé pryč), večerní
             špička 17-21 (vaření, TV, koupání). Víkendy plošší a o ~10 % vyšší (lidé doma).
             Baseline 15-25 % špičky (lednice, stand-by, malé spotřebiče).
           - **Kanceláře / administrativa** (office): JEDNODENNÍ špička 8-17, prudký pokles po
             17h, weekend a noc minimum (5-10 % peaku). Špička obvykle kolem 11-13.
           - **Průmysl / továrna nepřetržitá** (industrial 24/7): velmi PLOCHÝ profil, baseline
             80-95 % peaku, weekend ≈ workday. Žádné výrazné špičky.
           - **Průmysl jednosměnný** (industrial single-shift): silná špička 6-15, prudký pokles,
             weekend útlum na 10-30 %.
           - **Restaurace / gastro** (restaurant): VEČERNÍ špička 17-22, polední menší špička
             11-14, dopoledne útlum, weekend často VYŠŠÍ než všední.
           - **Škola** (school): pracovní okno 7-15, weekend úplný útlum (≤ 15 %), v létě (čvc/srp)
             celkový propad o 50-70 % kvůli prázdninám.
           - **Obchod / retail** (retail): otevírací doba 8-20, plošší vrchol mezi 10-17, weekend
             ≈ všední (často i vyšší u supermarketů).
           - **Zemědělství / kravín** (agri): konstantní zátěž (technologie chovu, dojení, ...);
             podobné průmyslu 24/7 ale s drobnými cykly.
           Pokud popis nesektoruje, odvoď z kontextu (kapacita, denní vzorec, sezónnost).

        TOPENÍ-DOMINANTNÍ specialita: pokud popis zmiňuje "topení", "vytápění",
        "v zimě výrazně víc", nebo zimní špičku, RANNÍ peak (5-7 h) je obvykle
        SILNĚJŠÍ než večerní — termostat reaguje na noční ochlazení a v 5-6h
        spustí maximum. Reálná data ukazují: zimní heating-dominantní objekty
        mají peak v 5-7 h, ne v 18-20 h. Profil je bimodální (ranní + večerní),
        ale s ranním vrcholem.

        3. SEZÓNNOST. Spotřeba ČR má YEARLY share přibližně:
           leden 11.5 %, únor 10.5 %, březen 9.5 %, duben 7.5 %, květen 6.0 %, červen 5.5 %,
           červenec 5.5 %, srpen 6.0 %, září 7.5 %, říjen 9.0 %, listopad 10.5 %, prosinec 11.0 %.
           Topení-dominantní objekty (rodinný dům s elektrickým topením, halové průmysly s vytápěním)
           mají VÝRAZNĚJŠÍ rozdíl léto/zima než tato základní křivka — leden může být i 15-20 %.
           Klimatizace-dominantní (datacenter, supermarket s mraznicí v létě) naopak invertuje.

        4. ANCHOR PRIORITY (rozhodovací strom):
           1) ★ CÍLOVÝ MĚSÍC kotva v popisu? ANO → použij ji ±10 %.
           2) DENNÍ kotvy ("550 kWh/den všední, 200 kWh/den víkend")? ANO → vynásob počtem dní.
           3) JINÉ MĚSÍCE kotev? ANO → odvoď cílový měsíc z výše uvedené sezónní křivky.
              Konzervativně.
           4) Žádné kotvy → použij yearly_consumption_kwh × měsíční podíl × 0.85×.
              (Roční číslo často reprezentuje historická data; aktuální měsíc může být
              o 15-25 % nižší kvůli změnám provozu, energetickým úsporám, nebo solární
              spotřebě klienta. Konzervativní discount kompenzuje tento bias.)

        5. BASELINE & PEAK & DENNÍ CYKLUS.
           - Detekuj baseline z popisu ("noční útlum", "stálá zátěž", "základní odběr"). Pokud
             popis říká "mizí v noci", baseline ≈ 5 % peaku. Pokud "běží i v noci", baseline ≥ 30 %.
           - Peak hodina: použij explicitní z popisu, jinak odvoď ze sektoru.
           - Plynulé přechody mezi baseline a peak — ne skok 0→peak.

        6. WEEKEND vs WORKDAY:
           - Popis "víkend ≈ všední" / "bez rozdílu" → weekend = workday přesně.
           - Popis "víkend výrazně méně" / "v sobotu zavřeno" → weekend 5-15 % všedního.
           - Popis "víkend o X % méně" → weekend = workday × (1 - X/100).
           - Popis "víkend vyšší" → weekend > workday (sektor: gastro, retail, residential).
           - Bez zmínky → odvoď ze sektoru (office: weekend = 0.1-0.2× weekday;
             residential: weekend = 1.05-1.10× weekday; industrial 24/7: weekend = 1.0× weekday).

        7. EXPECTED_MONTHLY_KWH:
           Vrať součet workday_kwh × počet všedních dní + weekend_kwh × počet víkendových dní
           jako sanity anchor. Měl by sedět ±5 % se součtem hodinových polí.

        VERIFIKACE PŘED ODESLÁNÍM (tichá kontrola):
        a) Součet (workday × #weekdays + weekend × #weekends) ≈ expected_monthly_kwh ±5 %.
        b) Baseline (min(workday)) > 0 pro všechny non-školy/non-restaurace bez nočního útlumu.
        c) Peak hodina není v noci (mimo data centers / strojírny s noční směnou).
        d) Pokud detekovaný sektor=residential, profil JE bimodální (dvě špičky AM+PM).
        e) Pokud detekovaný sektor=industrial 24/7, baseline ≥ 0.7× peak.

        Vrať POUZE validní JSON, bez markdownu, bez komentářů:

        {
          "workday_kwh_per_hour": [24 čísel ≥ 0],
          "weekend_kwh_per_hour": [24 čísel ≥ 0],
          "holiday_kwh_per_hour": [24 čísel ≥ 0] nebo null,
          "expected_monthly_kwh": číslo > 0,
          "reasoning": "stručné zdůvodnění (sektor, kde je špička, baseline, anchor)"
        }
      PROMPT
    end

    def extract_json(text)
      if text =~ /```(?:json)?\s*\n?(.*?)\n?\s*```/m
        $1.strip
      else
        text.strip
      end
    end

    def validate!(parsed)
      RESPONSE_KEYS.each do |key|
        arr = parsed[key]
        raise ExtractionError, "HourlyConsumptionParser: missing #{key}" unless arr.is_a?(Array)
        raise ExtractionError, "HourlyConsumptionParser: #{key} must have 24 values, got #{arr.size}" unless arr.size == 24
        unless arr.all? { |v| v.is_a?(Numeric) && v >= 0 }
          raise ExtractionError, "HourlyConsumptionParser: #{key} must contain non-negative numbers"
        end
      end

      if parsed["holiday_kwh_per_hour"]
        h = parsed["holiday_kwh_per_hour"]
        unless h.is_a?(Array) && h.size == 24 && h.all? { |v| v.is_a?(Numeric) && v >= 0 }
          raise ExtractionError, "HourlyConsumptionParser: holiday_kwh_per_hour invalid shape"
        end
      end

      unless parsed["expected_monthly_kwh"].is_a?(Numeric) && parsed["expected_monthly_kwh"] > 0
        raise ExtractionError, "HourlyConsumptionParser: missing or non-positive expected_monthly_kwh"
      end
    end

    def normalize!(parsed)
      parsed["workday_kwh_per_hour"] = parsed["workday_kwh_per_hour"].map(&:to_f)
      parsed["weekend_kwh_per_hour"] = parsed["weekend_kwh_per_hour"].map(&:to_f)
      parsed["holiday_kwh_per_hour"] = parsed["holiday_kwh_per_hour"]&.map(&:to_f)
      parsed["expected_monthly_kwh"] = parsed["expected_monthly_kwh"].to_f
    end
  end
end
