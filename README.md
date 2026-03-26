# Lupina

Extract structured data using Google Gemini LLM.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lupina'
```

And then execute:

    $ bundle install

## Usage

```ruby
require 'lupina'

Lupina.configure do |config|
  config.gemini_api_key = ENV.fetch('GEMINI_API_KEY')
  # config.model = "gemini-3-flash-preview" # optional, also configurable via LUPINA_MODEL env var
end

result = Lupina.extract(prompt: "Your prompt here, return JSON.")

# With an image:
result = Lupina.extract(prompt: "Describe this image as JSON.", image: "path/to/image.jpg")
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt.
