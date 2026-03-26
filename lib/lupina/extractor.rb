# frozen_string_literal: true

require "json"

module Lupina
  class Extractor
    def initialize(prompt:, image: nil, model:)
      @prompt = prompt
      @image = image
      @model = model
    end

    def call
      chat = RubyLLM.chat(model: @model)
      response = if @image
        chat.ask(@prompt, with: @image)
      else
        chat.ask(@prompt)
      end
      JSON.parse(extract_json(response.content))
    rescue JSON::ParserError => e
      raise ExtractionError, "Failed to parse LLM response as JSON: #{e.message}"
    end

    private

    def extract_json(text)
      if text =~ /```(?:json)?\s*\n?(.*?)\n?\s*```/m
        $1.strip
      else
        text.strip
      end
    end
  end
end
