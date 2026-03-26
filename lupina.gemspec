# frozen_string_literal: true

require_relative "lib/lupina/version"

Gem::Specification.new do |spec|
  spec.name = "lupina"
  spec.version = Lupina::VERSION
  spec.authors = [ "Papricek" ]
  spec.email = [ "patrikjira@gmail.com" ]

  spec.summary = "Extract structured data using Gemini LLM"
  spec.description = "Lupina extracts structured data via Google Gemini API. Purpose-agnostic foundation for LLM-powered extraction."
  spec.homepage = "https://github.com/papricek/lupina"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/papricek/lupina"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = [ "lib" ]

  spec.add_dependency "ruby_llm"
end
