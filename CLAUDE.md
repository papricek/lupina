# Lupina

Synthetic EDC export data generator for Czech solar plants. Natural language description in, 15-minute interval export (přetoky) CSV out. Uses Gemini LLM via `ruby_llm` gem.

## Structure

- `lib/lupina.rb` — main module, public API (`generate_edc`, `from_description`, `parse_description`)
- `lib/lupina/configuration.rb` — API key and model config
- `lib/lupina/extractor.rb` — sends prompts (with optional images) to Gemini, parses JSON response
- `lib/lupina/description_parser.rb` — LLM prompt that extracts capacity, yearly export, and export profiles from NL
- `lib/lupina/edc_generator.rb` — distributes monthly export across 15-min intervals using export profile × solar envelope
- `lib/lupina/solar_model.rb` — Czech solar constants (monthly shares, sunrise/sunset, specific yield)
- `examples/` — usage examples and verification scripts

## Commands

- `bin/setup` — install dependencies
- `bin/console` — interactive console
- `bundle exec rake` — run default tasks
