# Lupina

Ruby gem for extracting structured data via Google Gemini API using the `ruby_llm` gem.

## Structure

- `lib/lupina.rb` — main module, public API
- `lib/lupina/configuration.rb` — API key and model config
- `lib/lupina/extractor.rb` — sends prompts (with optional images) to Gemini, parses JSON response
- `examples/` — usage examples

## Commands

- `bin/setup` — install dependencies
- `bin/console` — interactive console
- `bundle exec rake` — run default tasks
