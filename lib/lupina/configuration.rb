# frozen_string_literal: true

module Lupina
  class Configuration
    attr_accessor :gemini_api_key, :model

    def initialize
      @model = ENV.fetch("LUPINA_MODEL", "gemini-3-flash-preview")
    end

    def apply!
      RubyLLM.configure do |config|
        config.gemini_api_key = gemini_api_key
      end
    end
  end
end
