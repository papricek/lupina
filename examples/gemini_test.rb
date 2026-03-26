# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load"
require "lupina"
require "json"

Lupina.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY")
end

result = Lupina.extract(
  prompt: 'Return a JSON object with a single key "status" and value "ok".'
)

puts JSON.pretty_generate(result)
