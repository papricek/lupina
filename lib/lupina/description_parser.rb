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
        Analyzuj následující popis solární elektrárny nebo odběratele elektřiny.

        Tvůj úkol:
        1. Určit zda jde o výrobnu (production) nebo spotřebitele (consumption)
        2. Extrahovat číselné parametry
        3. Vytvořit přesné 24-hodinové profily spotřeby zvlášť pro pracovní den, sobotu a neděli

        Profil spotřeby je pole 24 čísel (index 0 = půlnoc, index 12 = poledne, index 23 = 23:00).
        Každé číslo je 0.0 až 1.0 kde:
        - 1.0 = špičková spotřeba (maximum)
        - 0.0 = žádná spotřeba

        Tři profily pokrývají celý týden:
        - workday_profile: pondělí až pátek (běžný pracovní den)
        - saturday_profile: sobota (může se lišit — zkrácený provoz, dopolední směna, zavřeno...)
        - sunday_profile: neděle a svátky (obvykle zavřeno, ale kravín dojí i v neděli)

        Příklady:
        - Továrna (Po-Pá plný provoz, So dopoledne, Ne zavřeno):
          workday  [0.05,0.05,0.05,0.05,0.05,0.05,0.4,0.9,1.0,1.0,1.0,0.8,0.3,0.9,1.0,0.6,0.2,0.05,0.05,0.05,0.05,0.05,0.05,0.05]
          saturday [0.05,0.05,0.05,0.05,0.05,0.05,0.4,0.9,1.0,1.0,1.0,0.8,0.2,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05]
          sunday   [0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05,0.05]

        - Kravín (dojení denně 4-10h, chlazení mléka 24/7):
          workday  [0.15,0.15,0.15,0.15,1.0,1.0,1.0,1.0,0.9,0.8,0.4,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.2,0.2,0.15,0.15,0.15,0.15]
          saturday [0.15,0.15,0.15,0.15,1.0,1.0,1.0,1.0,0.9,0.8,0.4,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.2,0.2,0.15,0.15,0.15,0.15]
          sunday   [0.15,0.15,0.15,0.15,1.0,1.0,1.0,1.0,0.9,0.8,0.4,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.2,0.2,0.15,0.15,0.15,0.15]

        - Rodinný dům (lidi v práci Po-Pá, doma So-Ne):
          workday  [0.15,0.1,0.1,0.1,0.1,0.15,0.4,0.6,0.3,0.2,0.15,0.15,0.2,0.15,0.15,0.15,0.3,0.6,0.8,1.0,0.9,0.7,0.4,0.2]
          saturday [0.15,0.1,0.1,0.1,0.1,0.1,0.15,0.2,0.4,0.5,0.6,0.7,0.8,0.7,0.6,0.5,0.5,0.6,0.8,1.0,0.9,0.7,0.4,0.2]
          sunday   [0.15,0.1,0.1,0.1,0.1,0.1,0.15,0.2,0.3,0.5,0.6,0.7,0.8,0.7,0.6,0.5,0.4,0.5,0.7,0.9,0.8,0.6,0.4,0.2]

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
        - Pokud roční přetoky nejsou uvedeny ale "všechno jde do sítě", odhadni jako kapacita × 950.
        - Každý profil MUSÍ mít přesně 24 hodnot.
        - Profily musí přesně odrážet popis.
        - Sobota se často liší od neděle (zkrácený provoz, dopolední směna, ...).
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
