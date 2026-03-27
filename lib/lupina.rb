# frozen_string_literal: true

require "ruby_llm"

require_relative "lupina/version"
require_relative "lupina/configuration"
require_relative "lupina/extractor"
require_relative "lupina/solar_model"
require_relative "lupina/edc_generator"
require_relative "lupina/description_parser"

module Lupina
  class Error < StandardError; end
  class ExtractionError < Error; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration.apply!
    end

    def extract(prompt:, image: nil)
      Extractor.new(prompt: prompt, image: image, model: configuration.model).call
    end

    def generate_edc(capacity_kwp:, yearly_surplus_kwh:, month:, year: Date.today.year,
                     surplus_profile: nil, ean: "859182400110224391", seed: nil)
      generator = EdcGenerator.new(
        capacity_kwp: capacity_kwp, yearly_surplus_kwh: yearly_surplus_kwh,
        month: month, year: year, surplus_profile: surplus_profile,
        ean: ean, seed: seed
      )
      csv = generator.generate
      { csv: csv, stats: generator.stats }
    end

    def parse_description(description)
      DescriptionParser.new(description: description, model: configuration.model).call
    end

    def from_description(description, month:, year: Date.today.year, ean: "859182400110224391", seed: nil)
      params = parse_description(description)

      profile = {
        workday: params["workday_profile"],
        saturday: params["saturday_profile"],
        sunday: params["sunday_profile"]
      }

      if params["type"] == "production"
        result = generate_edc(
          capacity_kwp: params["capacity_kwp"],
          yearly_surplus_kwh: params["yearly_surplus_kwh"],
          month: month, year: year,
          surplus_profile: profile,
          ean: ean, seed: seed
        )
        result.merge(parsed: params)
      else
        raise Error, "Consumption EDC generation not yet implemented"
      end
    end
  end
end
