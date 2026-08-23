# frozen_string_literal: true

# Standalone pack validation entry point.
#
#   ruby lib/english_arcade/validate.rb
#
# Exits non-zero and prints every failure path when a pack breaks the
# contract, so content can be checked without booting Rails.
require "psych"
require_relative "pack_loader"

module EnglishArcade
  module Validate
    DEFAULT_DIRECTORY = File.expand_path("../../db/seeds/english_arcade", __dir__)

    def self.call(directory = DEFAULT_DIRECTORY, io: $stdout, strict: true)
      loader = PackLoader.new(directory)
      failures = 0
      total_items = 0
      total_cards = 0
      below_bar = []

      Schema::TARGETS.each do |target|
        pack = loader.load(target, validate: false)
        validator = PackValidator.new(pack, strict: strict)
        valid = validator.valid?
        count = pack["items"].is_a?(Array) ? pack["items"].size : 0
        cards = pack["cards"].is_a?(Array) ? pack["cards"].size : 0

        if valid
          total_items += count
          total_cards += cards
          below_bar << target if count < Schema::PUBLISHABLE_ITEMS_PER_TARGET
          io.puts "PASS #{target.ljust(14)} #{count} items, #{cards} cards"
          validator.warnings.each { |warning| io.puts "     WARN #{warning}" }
        else
          failures += 1
          io.puts "FAIL #{target.ljust(14)} #{count} items, #{cards} cards"
          validator.errors.each { |error| io.puts "     #{error}" }
        end
      rescue PackLoader::MissingPackError => error
        failures += 1
        io.puts "FAIL #{target}: #{error.message}"
      rescue Psych::SyntaxError => error
        failures += 1
        io.puts "FAIL #{target}: YAML syntax error: #{error.message}"
      end

      io.puts "---"
      io.puts "#{Schema::TARGETS.size - failures}/#{Schema::TARGETS.size} packs valid, #{total_items} items, #{total_cards} cards"
      io.puts "content gate: >= #{Schema::PUBLISHABLE_ITEMS_PER_TARGET} items per target"
      io.puts "below publishable bar: #{below_bar.join(", ")}" if below_bar.any?
      failures.zero? && below_bar.empty?
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(EnglishArcade::Validate.call ? 0 : 1)
end
