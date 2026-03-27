# frozen_string_literal: true

require "json"

module Lupina
  class DescriptionParser
    PROFILE_KEYS = %w[workday_profile saturday_profile sunday_profile].freeze

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

        Tvůj úkol:
        1. Určit zda jde o výrobnu (production) nebo spotřebitele (consumption)
        2. Extrahovat číselné parametry
        3. Vytvořit přesné 24-hodinové profily zvlášť pro pracovní den, sobotu a neděli

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

        PRO SPOTŘEBITELE (consumption):
        Profily popisují SPOTŘEBU objektu.
        - 1.0 = špičkový odběr (stroje naplno)
        - 0.05 = standby (zabezpečení)
        - 0.0 = žádná spotřeba

        Profil = pole 24 čísel (index 0 = půlnoc, index 12 = poledne, index 23 = 23:00).
        Tři profily: workday_profile (Po-Pá), saturday_profile, sunday_profile.

        Příklady profilů PŘETOKŮ (pro výrobny):
        - Přetoky jen odpoledne po 15h a o víkendech (stroje jedou do 15:00):
          workday  [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0.5,1.0,1.0,1.0,1.0,0.5,0,0,0]
          saturday [0,0,0,0,0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0,0,0,0]
          sunday   [0,0,0,0,0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0,0,0,0]

        - Přes týden stroje 7-17 s polední pauzou, přetoky jen o pauze a víkendy:
          workday  [0,0,0,0,0,0,0,0,0,0,0,0,0.8,0,0,0,0,0,0,0,0,0,0,0]
          saturday [0,0,0,0,0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0,0,0,0]
          sunday   [0,0,0,0,0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0,0,0,0]

        - Stodola/louka — nikdo nespotřebovává, plné přetoky vždy:
          workday  [0,0,0,0,0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0,0,0,0]
          saturday [0,0,0,0,0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0,0,0,0]
          sunday   [0,0,0,0,0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0,0,0,0]

        - Ranní směna 6-14, přetoky odpoledne + víkendy:
          workday  [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0.5,1.0,1.0,1.0,1.0,1.0,0.5,0,0,0]
          saturday [0,0,0,0,0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0,0,0,0]
          sunday   [0,0,0,0,0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0,0,0,0]

        Příklad profilu SPOTŘEBY (pro spotřebitele):
        - Pekárna 3-11 ráno, víkend zavřeno:
          workday  [0.05,0.05,0.05,0.3,0.8,1.0,1.0,1.0,1.0,1.0,1.0,0.5,0.1,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05]
          saturday [0.05,0.05,0.05,0.3,0.8,1.0,1.0,1.0,1.0,0.5,0.1,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05]
          sunday   [0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05]

        Vrať POUZE validní JSON, bez markdown, bez komentářů:

        {
          "type": "production" nebo "consumption",
          "capacity_kwp": číslo nebo null (jen pro production — špičkový výkon FVE v kWp),
          "yearly_surplus_kwh": číslo nebo null (jen pro production — roční přetoky v kWh),
          "yearly_consumption_kwh": číslo nebo null (jen pro consumption — roční spotřeba v kWh),
          "workday_profile": [24 čísel 0.0-1.0],
          "saturday_profile": [24 čísel 0.0-1.0],
          "sunday_profile": [24 čísel 0.0-1.0],
          "reasoning": "stručné zdůvodnění proč profily vypadají takto"
        }

        Pravidla:
        - Převeď MWh na kWh (1 MWh = 1000 kWh). Lidi často píšou "MW" místo "MWh".
        - Pokud kapacita není explicitně uvedena ale lze ji odvodit, odvoď ji.
        - Pokud roční přetoky nejsou uvedeny ale popis říká kolik se spotřebuje místně,
          spočítej: přetoky = (kapacita × 1000) - místní_spotřeba.
        - Pokud popis říká "všechno jde do sítě", odhadni přetoky jako kapacita × 950.
        - Každý profil MUSÍ mít přesně 24 hodnot.
        - Pro výrobnu: profily = podíl přetoků (1.0 = vše do sítě).
        - Pro spotřebitele: profily = úroveň spotřeby (1.0 = maximum odběru).
        - Sobota se často liší od neděle (zkrácený provoz, dopolední směna...).
        - Zemědělské provozy (kravíny, farmy) mají obvykle stejný profil celý týden.
        - Pokud popis zmiňuje stálý odběr (chlazení, servery), přidej base load i v noci a o víkendu.

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
    end

    def normalize!(parsed)
      parsed["capacity_kwp"] = parsed["capacity_kwp"]&.to_f
      parsed["yearly_surplus_kwh"] = parsed["yearly_surplus_kwh"]&.to_f
      parsed["yearly_consumption_kwh"] = parsed["yearly_consumption_kwh"]&.to_f
      PROFILE_KEYS.each { |k| parsed[k] = parsed[k].map(&:to_f) }
    end
  end
end
