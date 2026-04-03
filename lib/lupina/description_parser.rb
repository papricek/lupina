# frozen_string_literal: true

require "json"

module Lupina
  class DescriptionParser
    WEEKDAYS = %w[monday tuesday wednesday thursday friday saturday sunday].freeze
    PROFILE_KEYS = WEEKDAYS.map { |d| "#{d}_profile" }.freeze

    def initialize(description:, model:)
      @description = description
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
      raise ExtractionError, "Failed to parse LLM response as JSON: #{e.message}"
    end

    private

    def prompt
      <<~PROMPT
        Jsi expert na české fotovoltaické instalace a energetiku.
        Analyzuj následující popis a extrahuj strukturovaná data.

        KONTEXT — jak fungují přetoky:
        Solární elektrárna vyrobí za rok přibližně kapacita_kWp × 1000 kWh (čistá produkce).
        Část této elektřiny spotřebuje objekt sám (místní spotřeba), zbytek jde do sítě = PŘETOKY.
        Přetoky = produkce - místní spotřeba. Zákazník nám sdělí roční přetoky z loňska,
        abychom mohli odhadnout přetoky pro každý měsíc (v létě víc, v zimě míň).
        Profil přetoků říká KDY během dne přetoky nastávají — závisí na tom,
        kdy objekt spotřebovává a kdy ne.

        Tvůj úkol:
        1. Určit zda jde o výrobnu (production) nebo spotřebitele (consumption)
        2. Extrahovat číselné parametry
        3. Vytvořit přesné 24-hodinové profily ZVLÁŠŤ PRO KAŽDÝ DEN V TÝDNU (Po, Út, St, Čt, Pá, So, Ne)

        PRO VÝROBNU (production):
        Profily popisují PŘETOKY — jaký podíl vyrobené elektřiny jde do sítě v danou hodinu.
        - 1.0 = veškerá produkce v tu hodinu jde do sítě (žádná místní spotřeba)
        - 0.5 = polovina produkce do sítě, polovina spotřebována místně
        - 0.0 = žádné přetoky (vše spotřebováno místně)
        Generátor automaticky aplikuje solární křivku podle měsíce (v zimě slunce 8-16,
        v létě 5-21). Profil jen říká "kolik z toho co se vyrobí jde do sítě".
        Stačí 1.0 pro hodiny kdy přetoky ano, 0 kdy ne. Nemusí mít tvar zvonu.
        DŮLEŽITÉ: Pokud popis říká přetoky v určitou dobu, KAŽDÝ den daného typu
        (pracovní/sobota/neděle) bude mít přetoky podle profilu. Žádná náhodnost.

        OVĚŘENÍ KONZISTENCE: Spočítej poměr přetoků k produkci:
        poměr = roční_přetoky / (kapacita × 1000).
        - Poměr blízko 1.0 (>0.8) → minimální spotřeba, profily skoro všude 1.0
        - Poměr 0.3-0.8 → střední spotřeba, profily odpovídají popisu
        - Poměr <0.3 → vysoká spotřeba, přetoky jen ve špičkách (pauza, víkend)
        Profily musí být konzistentní s tímto poměrem.

        PRO SPOTŘEBITELE (consumption):
        Profily popisují SPOTŘEBU objektu.
        - 1.0 = špičkový odběr (stroje naplno)
        - 0.05 = standby (zabezpečení)
        - 0.0 = žádná spotřeba

        Profil = pole 24 čísel (index 0 = půlnoc, index 12 = poledne, index 23 = 23:00).
        Sedm profilů — jeden pro KAŽDÝ den v týdnu:
        monday_profile, tuesday_profile, wednesday_profile, thursday_profile,
        friday_profile, saturday_profile, sunday_profile.
        Pokud mají některé dny stejný profil, prostě opakuj stejné pole.
        Díky tomu lze vyjádřit JAKÝKOLIV rozvrh (např. přetoky jen ve středu a o víkendu).

        Příklady profilů PŘETOKŮ (pro výrobny):
        FULL = [0,0,0,0,0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0,0,0,0]
        ZERO = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

        - Přetoky jen odpoledne po 15h a o víkendech (stroje jedou Po-Pá do 15:00):
          Po-Pá   [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0.5,1.0,1.0,1.0,1.0,0.5,0,0,0]
          So+Ne    FULL

        - Přetoky jen o víkendech a ve středu celý den (Po,Út,Čt,Pá plná spotřeba):
          Po       ZERO
          Út       ZERO
          St       FULL
          Čt       ZERO
          Pá       ZERO
          So       FULL
          Ne       FULL

        - Stodola/louka — nikdo nespotřebovává, plné přetoky vždy:
          Po-Ne    FULL (všech 7 profilů stejných)

        - Ranní směna 6-14, přetoky odpoledne + víkendy:
          Po-Pá   [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0.5,1.0,1.0,1.0,1.0,1.0,0.5,0,0,0]
          So+Ne    FULL

        Příklad profilu SPOTŘEBY (pro spotřebitele):
        - Pekárna 3-11 ráno, víkend zavřeno:
          Po-Pá   [0.05,0.05,0.05,0.3,0.8,1.0,1.0,1.0,1.0,1.0,1.0,0.5,0.1,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05]
          So       [0.05,0.05,0.05,0.3,0.8,1.0,1.0,1.0,1.0,0.5,0.1,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05]
          Ne       [0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05]

        DŮLEŽITÉ: V příkladech výše je zkrácený zápis (Po-Pá, FULL, ZERO).
        V JSON odpovědi MUSÍŠ vždy vypsat všech 7 profilů jako plné pole 24 čísel!

        === POKROČILÉ FUNKCE (volitelné — vyplň JEN pokud popis explicitně vyžaduje) ===

        "holiday_profile": [24 čísel] nebo null
          Profil pro české státní svátky (1.1., Velikonoční po., 1.5., 8.5., 5.7., 6.7.,
          28.9., 28.10., 17.11., 24-26.12.). Generátor svátky zná automaticky.
          Typicky = sunday_profile (zavřeno → plné přetoky / minimální spotřeba).
          Null = svátky se neliší od normálního dne.

        "shutdown_periods": [{"from":"MM-DD","to":"MM-DD"}] nebo []
          Celozávodní dovolená, plánované odstávky. Tyto dny použijí holiday_profile.
          Příklad: [{"from":"07-01","to":"07-14"}]

        "seasonal_overrides": [...] nebo []
          Pro profily závislé na ročním období (školy v létě, sezónní provozy).
          Každý override: {"months":[7,8], "monday_profile":[24], ..., "sunday_profile":[24],
          "holiday_profile":[24] nebo null}. Základní profily platí pro měsíce BEZ override.

        "monthly_consumption_weights": [12 čísel] nebo null (JEN pro consumption)
          Sezónní váhy spotřeby (index 0=leden, 11=prosinec). Vyšší číslo = větší spotřeba.
          Tepelné čerpadlo: [1.8,1.5,1.2,1.0,0.7,0.5,0.4,0.5,0.7,1.0,1.4,1.7]
          Klimatizace: [0.6,0.6,0.8,1.0,1.2,1.5,1.8,1.7,1.2,0.9,0.7,0.6]

        "battery_kwh": číslo nebo null (JEN pro production)
          Kapacita bateriového úložiště v kWh. Posouvá přetoky — ráno se plní, přetoky začnou později.

        "day_frequency": {"monday":0.4, ...} nebo null
          Pravděpodobnost 0.0-1.0 že daný den je aktivní. Pro sporadické vzory ("2-3× týdně" = ~0.4).
          Nezmíněné dny = vždy aktivní.

        Příklad pokročilých funkcí — škola s prázdninami:
          Základní profily (školní rok): Po-Pá přetoky po 15h, So+Ne FULL
          holiday_profile: FULL (o svátcích zavřeno)
          seasonal_overrides: [{"months":[7,8], všech 7 profilů = FULL, holiday_profile: FULL}]
          shutdown_periods: [{"from":"12-23","to":"01-02"}]

        Vrať POUZE validní JSON, bez markdown, bez komentářů:

        {
          "type": "production" nebo "consumption",
          "capacity_kwp": číslo nebo null (jen pro production — špičkový výkon FVE v kWp),
          "yearly_surplus_kwh": číslo nebo null (jen pro production — roční přetoky v kWh),
          "yearly_consumption_kwh": číslo nebo null (jen pro consumption — roční spotřeba v kWh),
          "monday_profile": [24 čísel 0.0-1.0],
          "tuesday_profile": [24 čísel 0.0-1.0],
          "wednesday_profile": [24 čísel 0.0-1.0],
          "thursday_profile": [24 čísel 0.0-1.0],
          "friday_profile": [24 čísel 0.0-1.0],
          "saturday_profile": [24 čísel 0.0-1.0],
          "sunday_profile": [24 čísel 0.0-1.0],
          "holiday_profile": [24 čísel 0.0-1.0] nebo null,
          "shutdown_periods": [{"from":"MM-DD","to":"MM-DD"}] nebo [],
          "seasonal_overrides": [{"months":[1-12],"monday_profile":[24],...,"sunday_profile":[24],"holiday_profile":[24] nebo null}] nebo [],
          "monthly_consumption_weights": [12 čísel] nebo null,
          "battery_kwh": číslo nebo null,
          "day_frequency": {"monday":0.0-1.0,...} nebo null,
          "reasoning": "stručné zdůvodnění proč profily vypadají takto"
        }

        Pravidla:
        - Převeď MWh na kWh (1 MWh = 1000 kWh). Lidi často píšou "MW" místo "MWh".
        - Pokud kapacita není explicitně uvedena ale lze ji odvodit, odvoď ji.
        - Pokud roční přetoky nejsou uvedeny ale popis říká kolik se spotřebuje místně,
          spočítej: přetoky = (kapacita × 1000) - místní_spotřeba.
        - Pokud popis říká "všechno jde do sítě", odhadni přetoky jako kapacita × 950.
        - Roční přetoky nemohou překročit roční produkci (kapacita × 1000).
          Pokud zadaná čísla nedávají smysl, upozorni v reasoning.
        - Každý profil MUSÍ mít přesně 24 hodnot. MUSÍ být přesně 7 profilů (Po-Ne).
        - Pro výrobnu: profily = podíl přetoků (1.0 = vše do sítě).
        - Pro spotřebitele: profily = úroveň spotřeby (1.0 = maximum odběru).
        - Sobota se často liší od neděle (zkrácený provoz, dopolední směna...).
        - Zemědělské provozy (kravíny, farmy) mají obvykle stejný profil celý týden.
        - Pokud popis zmiňuje stálý odběr (chlazení, servery), přidej base load i v noci a o víkendu.
        - Pokud popis specifikuje konkrétní dny (např. "jen ve středu"), nastav profil POUZE
          pro tyto dny a ostatní dny nastav na nulu (nebo naopak podle kontextu).
        - Pokročilé funkce (holiday_profile, shutdown_periods, seasonal_overrides,
          monthly_consumption_weights, battery_kwh, day_frequency) používej JEN když
          je popis explicitně vyžaduje. Jinak nastav na null nebo [].

        Popis k analýze:
        "#{@description}"
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
      type = parsed["type"]
      raise ExtractionError, "Unknown type: #{type}" unless %w[production consumption].include?(type)

      if type == "production"
        raise ExtractionError, "Missing capacity_kwp" unless parsed["capacity_kwp"]
        raise ExtractionError, "Missing yearly_surplus_kwh" unless parsed["yearly_surplus_kwh"]
      end

      if type == "consumption"
        raise ExtractionError, "Missing yearly_consumption_kwh" unless parsed["yearly_consumption_kwh"]
      end

      PROFILE_KEYS.each do |key|
        profile = parsed[key]
        raise ExtractionError, "Missing #{key}" unless profile.is_a?(Array)
        raise ExtractionError, "#{key} must have 24 values, got #{profile.size}" unless profile.size == 24
        unless profile.all? { |v| v.is_a?(Numeric) && v >= 0 && v <= 1.0 }
          raise ExtractionError, "#{key} values must be 0.0-1.0"
        end
      end

      validate_optional_profile!(parsed, "holiday_profile")
      validate_shutdown_periods!(parsed)
      validate_seasonal_overrides!(parsed)
      validate_monthly_consumption_weights!(parsed)
      validate_battery_kwh!(parsed)
      validate_day_frequency!(parsed)
    end

    def validate_optional_profile!(parsed, key)
      profile = parsed[key]
      return unless profile.is_a?(Array)
      raise ExtractionError, "#{key} must have 24 values" unless profile.size == 24
      unless profile.all? { |v| v.is_a?(Numeric) && v >= 0 && v <= 1.0 }
        raise ExtractionError, "#{key} values must be 0.0-1.0"
      end
    end

    def validate_shutdown_periods!(parsed)
      periods = parsed["shutdown_periods"]
      return unless periods.is_a?(Array) && periods.any?
      periods.each do |p|
        raise ExtractionError, "shutdown_periods entries must have 'from' and 'to'" unless p["from"] && p["to"]
        unless p["from"].match?(/\A\d{2}-\d{2}\z/) && p["to"].match?(/\A\d{2}-\d{2}\z/)
          raise ExtractionError, "shutdown_periods dates must be MM-DD format"
        end
      end
    end

    def validate_seasonal_overrides!(parsed)
      overrides = parsed["seasonal_overrides"]
      return unless overrides.is_a?(Array) && overrides.any?
      overrides.each do |override|
        raise ExtractionError, "seasonal_overrides must have 'months'" unless override["months"].is_a?(Array)
        PROFILE_KEYS.each do |key|
          profile = override[key]
          raise ExtractionError, "seasonal_override missing #{key}" unless profile.is_a?(Array)
          raise ExtractionError, "seasonal_override #{key} must have 24 values" unless profile.size == 24
        end
        validate_optional_profile!(override, "holiday_profile")
      end
    end

    def validate_monthly_consumption_weights!(parsed)
      weights = parsed["monthly_consumption_weights"]
      return unless weights.is_a?(Array)
      raise ExtractionError, "monthly_consumption_weights must have 12 values" unless weights.size == 12
      unless weights.all? { |v| v.is_a?(Numeric) && v > 0 }
        raise ExtractionError, "monthly_consumption_weights must be positive numbers"
      end
    end

    def validate_battery_kwh!(parsed)
      val = parsed["battery_kwh"]
      return unless val
      unless val.is_a?(Numeric) && val > 0
        raise ExtractionError, "battery_kwh must be a positive number"
      end
    end

    def validate_day_frequency!(parsed)
      freq = parsed["day_frequency"]
      return unless freq.is_a?(Hash)
      freq.each do |day, val|
        unless WEEKDAYS.include?(day)
          raise ExtractionError, "day_frequency key '#{day}' is not a valid weekday"
        end
        unless val.is_a?(Numeric) && val >= 0 && val <= 1.0
          raise ExtractionError, "day_frequency values must be 0.0-1.0"
        end
      end
    end

    def normalize!(parsed)
      parsed["capacity_kwp"] = parsed["capacity_kwp"]&.to_f
      parsed["yearly_surplus_kwh"] = parsed["yearly_surplus_kwh"]&.to_f
      parsed["yearly_consumption_kwh"] = parsed["yearly_consumption_kwh"]&.to_f
      PROFILE_KEYS.each { |k| parsed[k] = parsed[k].map(&:to_f) }

      if parsed["holiday_profile"].is_a?(Array)
        parsed["holiday_profile"] = parsed["holiday_profile"].map(&:to_f)
      end

      if parsed["shutdown_periods"].is_a?(Array)
        parsed["shutdown_periods"] = parsed["shutdown_periods"].map do |p|
          { "from" => p["from"], "to" => p["to"] }
        end
      end

      if parsed["seasonal_overrides"].is_a?(Array)
        parsed["seasonal_overrides"] = parsed["seasonal_overrides"].map do |override|
          normalized = { "months" => override["months"].map(&:to_i) }
          PROFILE_KEYS.each { |k| normalized[k] = override[k].map(&:to_f) }
          if override["holiday_profile"].is_a?(Array)
            normalized["holiday_profile"] = override["holiday_profile"].map(&:to_f)
          end
          normalized
        end
      end

      if parsed["monthly_consumption_weights"].is_a?(Array)
        weights = parsed["monthly_consumption_weights"].map(&:to_f)
        total = weights.sum
        parsed["monthly_consumption_weights"] = weights.map { |w| w / total * 12.0 }
      end

      parsed["battery_kwh"] = parsed["battery_kwh"]&.to_f

      if parsed["day_frequency"].is_a?(Hash)
        parsed["day_frequency"] = parsed["day_frequency"].transform_values(&:to_f)
      end
    end
  end
end
