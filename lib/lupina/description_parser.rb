# frozen_string_literal: true

require "json"

module Lupina
  class DescriptionParser
    AVAILABLE_PATTERNS = %w[
      minimal afternoon_weekend industrial_lunch_break early_shift residential flat
    ].freeze

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
        Analyzuj následující popis solární elektrárny nebo odběratele elektřiny a extrahuj strukturované parametry.

        Dostupné vzory spotřeby (consumption_pattern):
        - "minimal" — téměř nulová místní spotřeba, skoro vše se exportuje do sítě (stodoly, FVE na louce, prázdné budovy)
        - "afternoon_weekend" — vysoká spotřeba ráno ve všední dny, klesá odpoledne, nízká o víkendech (kanceláře, obchody)
        - "industrial_lunch_break" — stroje jedou celý den ve všední dny, přetoky jen přes polední pauzu 12-13, víkendy plné přetoky (továrny, dílny s nepřetržitým provozem)
        - "early_shift" — ranní směna 6-14 ve všední dny, odpolední přetoky + celé víkendy (výroba s ranní směnou, kravíny s ranním dojením)
        - "residential" — nízká spotřeba přes den (lidi v práci), vysoká večer (rodinné domy, byty, chaty)
        - "flat" — rovnoměrná spotřeba celý den (serverovny, chlazení, stálý odběr)

        Vrať POUZE validní JSON, bez markdown, bez komentářů:

        {
          "type": "production" nebo "consumption",
          "capacity_kwp": číslo nebo null (jen pro production — špičkový výkon FVE v kWp),
          "yearly_surplus_kwh": číslo nebo null (jen pro production — roční přetoky do sítě v kWh),
          "yearly_consumption_kwh": číslo nebo null (jen pro consumption — roční spotřeba v kWh),
          "consumption_pattern": jeden z #{AVAILABLE_PATTERNS.inspect},
          "reasoning": "stručné zdůvodnění proč jsi zvolil tento vzor"
        }

        Pravidla:
        - Převeď MWh na kWh (1 MWh = 1000 kWh). Lidi často píšou "MW" místo "MWh".
        - Pokud kapacita není explicitně uvedena ale lze ji odvodit, odvoď ji.
        - Pokud roční přetoky nejsou uvedeny číslem ale popis naznačuje "všechno jde do sítě", odhadni jako kapacita × 950 kWh/kWp.
        - Pokud roční spotřeba není uvedena ale je uveden popis, odhadni rozumnou hodnotu.
        - Vyber consumption_pattern, který nejlépe odpovídá popsanému využití.
        - U production typu: roční přetoky NESMÍ překročit kapacita × 1000 (to je fyzický limit výroby).

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

      pattern = parsed["consumption_pattern"]
      unless AVAILABLE_PATTERNS.include?(pattern)
        raise ExtractionError, "Unknown consumption_pattern: #{pattern}"
      end

      if type == "production"
        raise ExtractionError, "Missing capacity_kwp for production" unless parsed["capacity_kwp"]
        raise ExtractionError, "Missing yearly_surplus_kwh for production" unless parsed["yearly_surplus_kwh"]
      end

      if type == "consumption"
        raise ExtractionError, "Missing yearly_consumption_kwh for consumption" unless parsed["yearly_consumption_kwh"]
      end
    end

    def normalize!(parsed)
      parsed["capacity_kwp"] = parsed["capacity_kwp"]&.to_f
      parsed["yearly_surplus_kwh"] = parsed["yearly_surplus_kwh"]&.to_f
      parsed["yearly_consumption_kwh"] = parsed["yearly_consumption_kwh"]&.to_f
      parsed["consumption_pattern"] = parsed["consumption_pattern"].to_sym
    end
  end
end
