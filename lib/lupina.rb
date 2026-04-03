# frozen_string_literal: true

require "ruby_llm"

require_relative "lupina/version"
require_relative "lupina/configuration"
require_relative "lupina/extractor"
require_relative "lupina/solar_model"
require_relative "lupina/czech_holidays"
require_relative "lupina/day_resolver"
require_relative "lupina/edc_generator"
require_relative "lupina/consumption_edc_generator"
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
                     surplus_profile: nil, holiday_profile: nil, shutdown_periods: nil,
                     seasonal_overrides: nil, battery_kwh: nil, day_frequency: nil,
                     ean: "859182400110224391", seed: nil)
      yearly_production = capacity_kwp.to_f * SolarModel::SPECIFIC_YIELD
      if yearly_surplus_kwh.to_f > yearly_production
        raise Error, "Yearly export (#{yearly_surplus_kwh} kWh) exceeds estimated production " \
                     "(#{capacity_kwp} kWp × #{SolarModel::SPECIFIC_YIELD} = #{yearly_production.round(0)} kWh)"
      end

      generator = EdcGenerator.new(
        capacity_kwp: capacity_kwp, yearly_surplus_kwh: yearly_surplus_kwh,
        month: month, year: year, surplus_profile: surplus_profile,
        holiday_profile: holiday_profile, shutdown_periods: shutdown_periods,
        seasonal_overrides: seasonal_overrides, battery_kwh: battery_kwh,
        day_frequency: day_frequency, ean: ean, seed: seed
      )
      csv = generator.generate
      { csv: csv, stats: generator.stats }
    end

    def generate_consumption_edc(yearly_consumption_kwh:, month:, year: Date.today.year,
                                 consumption_profile: nil, holiday_profile: nil,
                                 shutdown_periods: nil, seasonal_overrides: nil,
                                 monthly_consumption_weights: nil, day_frequency: nil,
                                 ean: "859182400110224391", seed: nil)
      generator = ConsumptionEdcGenerator.new(
        yearly_consumption_kwh: yearly_consumption_kwh,
        month: month, year: year, consumption_profile: consumption_profile,
        holiday_profile: holiday_profile, shutdown_periods: shutdown_periods,
        seasonal_overrides: seasonal_overrides,
        monthly_consumption_weights: monthly_consumption_weights,
        day_frequency: day_frequency, ean: ean, seed: seed
      )
      csv = generator.generate
      { csv: csv, stats: generator.stats }
    end

    def parse_description(description)
      DescriptionParser.new(description: description, model: configuration.model).call
    end

    def from_description(description, month:, year: Date.today.year, ean: "859182400110224391", seed: nil)
      params = parse_description(description)

      profile = DescriptionParser::WEEKDAYS.each_with_object({}) do |day, h|
        h[day.to_sym] = params["#{day}_profile"]
      end

      advanced = extract_advanced_options(params)

      if params["type"] == "production"
        result = generate_edc(
          capacity_kwp: params["capacity_kwp"],
          yearly_surplus_kwh: params["yearly_surplus_kwh"],
          month: month, year: year,
          surplus_profile: profile,
          ean: ean, seed: seed,
          **advanced
        )
        result.merge(parsed: params)
      else
        result = generate_consumption_edc(
          yearly_consumption_kwh: params["yearly_consumption_kwh"],
          month: month, year: year,
          consumption_profile: profile,
          ean: ean, seed: seed,
          **advanced
        )
        result.merge(parsed: params)
      end
    end

    def extract_advanced_options(parsed)
      opts = {}

      if parsed["holiday_profile"].is_a?(Array)
        opts[:holiday_profile] = parsed["holiday_profile"]
      end

      if parsed["shutdown_periods"].is_a?(Array) && parsed["shutdown_periods"].any?
        opts[:shutdown_periods] = parsed["shutdown_periods"].map do |p|
          { from: p["from"], to: p["to"] }
        end
      end

      if parsed["seasonal_overrides"].is_a?(Array) && parsed["seasonal_overrides"].any?
        opts[:seasonal_overrides] = parsed["seasonal_overrides"].map do |override|
          so = {
            months: override["months"],
            profiles: DescriptionParser::WEEKDAYS.each_with_object({}) do |day, h|
              h[day.to_sym] = override["#{day}_profile"]
            end
          }
          if override["holiday_profile"].is_a?(Array)
            so[:holiday_profile] = override["holiday_profile"]
          end
          so
        end
      end

      if parsed["monthly_consumption_weights"].is_a?(Array)
        opts[:monthly_consumption_weights] = parsed["monthly_consumption_weights"]
      end

      if parsed["battery_kwh"].is_a?(Numeric) && parsed["battery_kwh"] > 0
        opts[:battery_kwh] = parsed["battery_kwh"]
      end

      if parsed["day_frequency"].is_a?(Hash)
        opts[:day_frequency] = parsed["day_frequency"].each_with_object({}) do |(day, freq), h|
          h[day.to_sym] = freq
        end
      end

      opts
    end
  end
end
