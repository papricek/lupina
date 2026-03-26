# frozen_string_literal: true

require "ruby_llm"

require_relative "lupina/version"
require_relative "lupina/configuration"
require_relative "lupina/extractor"

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
  end
end
