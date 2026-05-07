# frozen_string_literal: true

require "json"

module Lupina
  # Alternative parser path: instead of returning relative 0..1 profile shapes
  # that the generator multiplies by a solar envelope and renormalizes to a
  # yearly target, this parser asks the LLM to produce ABSOLUTE kWh values per
  # hour for a typical workday, weekend, and holiday at the given installation
  # in the given month.
  #
  # The LLM takes on more responsibility — it accounts for self-consumption,
  # inverter behavior, factory shifts, and any hints in the description — and
  # the downstream extrapolator just upsamples the hourly curve to 15-minute
  # intervals with mild noise.
  #
  # Designed to be tuned by autoresearch: the prompt is the primary knob, the
  # response shape is fixed, and validation is lightweight.
  class HourlyProfileParser
    RESPONSE_KEYS = %w[workday_kwh_per_hour weekend_kwh_per_hour].freeze

    def initialize(description:, capacity_kwp:, month:, year:, yearly_surplus_kwh: nil, model:)
      @description = description.to_s.strip
      @capacity_kwp = capacity_kwp.to_f
      @month = month.to_i
      @year = year.to_i
      @yearly_surplus_kwh = yearly_surplus_kwh&.to_f
      @model = model
    end

    def call
      chat = RubyLLM.chat(model: @model)
      response = chat.ask(prompt)
      parsed = JSON.parse(extract_json(response.content))
      validate!(parsed)
      normalize!(parsed)
      parsed
    rescue JSON::ParserError => e
      raise ExtractionError, "HourlyProfileParser: failed to parse LLM response as JSON: #{e.message}"
    end

    private

    MONTH_NAMES_CS = {
      1 => "leden", 2 => "únor", 3 => "březen", 4 => "duben",
      5 => "květen", 6 => "červen", 7 => "červenec", 8 => "srpen",
      9 => "září", 10 => "říjen", 11 => "listopad", 12 => "prosinec"
    }.freeze

    def prompt
      yearly_hint = if @yearly_surplus_kwh
        sprintf("Roční přetoky uvedené zákazníkem: %.0f kWh (= %.1f MWh).", @yearly_surplus_kwh, @yearly_surplus_kwh / 1000.0)
      else
        "Roční přetoky neznáme, odhadni z popisu."
      end

      anchors = AnchorExtractor.call(@description)
      anchor_block = AnchorExtractor.format_for_prompt(anchors, target_month: @month)

      <<~PROMPT
        Jsi expert na české fotovoltaické instalace, energetiku a 15min EDC data.
        Tvoje úloha: odhadnout PROFIL PŘETOKŮ pro jeden konkrétní měsíc v ABSOLUTNÍCH KWH PER HODINU.

        VSTUPY:
        Měsíc: #{MONTH_NAMES_CS[@month]} #{@year} (číslo měsíce: #{@month})
        Špičkový výkon FVE: #{@capacity_kwp} kWp
        #{yearly_hint}

        #{anchor_block}Popis zákazníka:
        "#{@description}"

        ÚKOL:
        Vrať tři pole po 24 číslech (jedno číslo per hodinu, hodiny 0-23 v MÍSTNÍM čase Europe/Prague,
        v dubnu už platí letní čas):
        - "workday_kwh_per_hour": kolik kWh PŘETEČE do sítě v dané hodině typického všedního dne
        - "weekend_kwh_per_hour": totéž pro typický víkendový den
        - "holiday_kwh_per_hour": totéž pro státní svátek (volitelné, null = stejné jako víkend)

        ZÁSADNÍ PRINCIPY:
        1. Hodnoty jsou ABSOLUTNÍ kWh za jednu hodinu, NE relativní 0-1.
           Příklad: dům 10 kWp s mírnou vlastní spotřebou v dubnu, kolem poledne ~3 kWh/h
           do sítě, ráno/večer ~0.5 kWh/h, v noci 0.0.
        2. Hodnoty MUSÍ odpovídat fyzikálním limitům: žádná hodina nesmí překročit
           kapacita_kWp (špičkový výkon × 1 hodina = max kWh/h). Ale typicky je špička
           60-90 % kapacity (mraky, úhel slunce, vlastní spotřeba). Pro #{@capacity_kwp} kWp
           v měsíci #{@month} je rozumný strop kolem #{(@capacity_kwp * solar_peak_fraction).round(1)} kWh/h.
        3. V noci (před východem / po západu slunce) MUSÍ být 0.0. Typický slunovrat:
           leden ~8-16, duben ~6-20, červenec ~5-21, říjen ~7-18 (vše místní čas).
        4. Tvar křivky odráží spotřebu objektu a typ instalace:
           - **Domácí FVE / malé instalace s úzkým oknem** (popis říká "profil úzký 9-17",
             "domácí FVE", "malá FVE", "špička 11-14"): křivka má JASNÝ JEDEN VRCHOL,
             peak hodina je ~2-3× průměrná hodnota přes aktivní okno.
             Příklad pro 10 kWp duben, peak ~3 kWh/h, ranní/večerní hraniční hodiny ~0.5-1 kWh/h.
             NE plochý profil — jasná zvonová křivka.
           - **Komerční / průmyslové s denní spotřebou** ("továrna", "dílna", "kanceláře",
             "kravín"): propad přes vlastní spotřebu ve dne, plošší vrchol, víkend výrazně víc.
           - **Atypicky ploché profily** (popis explicitně říká "atypicky plochý",
             "rovnoměrně přes celý den", "bez výrazného vrcholu"): generuj SKUTEČNĚ plochou
             křivku — peak hodina jen 1.1-1.2× průměru aktivního okna.
           Sleduj konkrétní fráze: "domácnost", "víkend zavřeno", "celodenní provoz",
           "špička 11–15", "atypicky plochý profil" atd.
        5. KRITICKÉ — anchor priority:
           a) Konkrétní čísla pro CÍLOVÝ MĚSÍC v popisu (např. "v dubnu skoro 6 MWh",
              "duben přes 1 150 kWh") → POUŽIJ PŘÍMO jako součet měsíce.
           b) Konkrétní DENNÍ čísla v popisu (např. "270 kWh/den o víkendu",
              "92 kWh/den") → použij přímo, vynásob počtem dní v měsíci.
           c) Konkrétní čísla pro JINÝ měsíc (např. "srpen 900 kWh, listopad pod 250") →
              odhadni cílový měsíc úměrně sezónnosti (jaro = ~50% léta, zima = ~25% léta).
           d) Roční číslo "yearly_surplus_kwh" (uvedeno výše jako vstup) je často
              nepřesné — používej HO POSLEDNÍ. Pokud popis indikuje výrazně méně/víc
              než ročně × měsíční podíl, VĚŘ POPISU a v reasoning to vysvětli.
           Příklad: yearly=7000, popis "domácí FVE, srpen 900 kWh, jarní rozjezd od března",
           cílový měsíc duben → odhad 400-500 kWh (= ~50% srpna), NE ~630 kWh
           (= 7000 × dubnový podíl 0.09).
        6. Pokud popis říká "východně orientované panely" nebo "ranní špička",
           posuň vrchol křivky před poledne. Pokud nic neříká, vrchol je 12-14h.
        7. Vrať ještě "expected_monthly_kwh" — tvůj odhad celkového měsíčního přetoku
           v kWh (= součet hodinových za workday × počet všedních dnů + víkend × víkendových).
           Toto je SANITY ANCHOR pro extrapolátor.

        SPECIÁLNÍ PŘÍPADY:
        - Pokud popis výrazně rozporuje roční číslo (např. zákazník tvrdí 25 MWh/rok ale
          popisuje "domácnost 10 kWp s minimální spotřebou v dubnu", odpovídá ~500 kWh
          v dubnu = ~6 MWh/rok), VĚŘ POPISU a vyrob hodinové hodnoty odpovídající popisu.
          Důvod uveď v "reasoning".

        Vrať POUZE validní JSON, bez markdownu, bez komentářů:

        {
          "workday_kwh_per_hour": [24 čísel ≥ 0],
          "weekend_kwh_per_hour": [24 čísel ≥ 0],
          "holiday_kwh_per_hour": [24 čísel ≥ 0] nebo null,
          "expected_monthly_kwh": číslo > 0,
          "reasoning": "stručné zdůvodnění (co jsi vzal jako anchor, kde je špička, proč daný tvar)"
        }
      PROMPT
    end

    # April share for production at Czech latitude is about 11% of yearly.
    # Peak hour at solar noon is roughly 60% of capacity for a typical clear day.
    # We use this only as a hint inside the prompt, not as a hard cap.
    def solar_peak_fraction
      case @month
      when 5, 6, 7, 8 then 0.85
      when 4, 9 then 0.75
      when 3, 10 then 0.6
      when 2, 11 then 0.45
      else 0.35
      end
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
        raise ExtractionError, "HourlyProfileParser: missing #{key}" unless arr.is_a?(Array)
        raise ExtractionError, "HourlyProfileParser: #{key} must have 24 values, got #{arr.size}" unless arr.size == 24
        unless arr.all? { |v| v.is_a?(Numeric) && v >= 0 }
          raise ExtractionError, "HourlyProfileParser: #{key} must contain non-negative numbers"
        end
      end

      if parsed["holiday_kwh_per_hour"] && !parsed["holiday_kwh_per_hour"].nil?
        h = parsed["holiday_kwh_per_hour"]
        unless h.is_a?(Array) && h.size == 24 && h.all? { |v| v.is_a?(Numeric) && v >= 0 }
          raise ExtractionError, "HourlyProfileParser: holiday_kwh_per_hour invalid shape"
        end
      end

      unless parsed["expected_monthly_kwh"].is_a?(Numeric) && parsed["expected_monthly_kwh"] > 0
        raise ExtractionError, "HourlyProfileParser: missing or non-positive expected_monthly_kwh"
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
