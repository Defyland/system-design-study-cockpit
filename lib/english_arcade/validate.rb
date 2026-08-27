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
      loaded_packs = {}
      pack_validity = {}

      Schema::TARGETS.each do |target|
        pack = loader.load(target, validate: false)
        loaded_packs[target] = pack
        validator = PackValidator.new(pack, strict: strict)
        valid = validator.valid?
        pack_validity[target] = valid
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
        pack_validity[target] = false
        io.puts "FAIL #{target}: #{error.message}"
      rescue Psych::SyntaxError => error
        failures += 1
        pack_validity[target] = false
        io.puts "FAIL #{target}: YAML syntax error: #{error.message}"
      end

      cross_pack_errors = PackValidator.cross_pack_prompt_errors(loaded_packs)
      invalid_targets = pack_validity.filter_map { |target, valid| target if !valid }
      cross_pack_errors = cross_pack_errors.reject do |error|
        target = error[/\Atarget=([^;]+);/, 1]
        error.include?("collection=items;") && invalid_targets.include?(target)
      end
      unless cross_pack_errors.empty?
        failures += 1
        io.puts "FAIL cross-pack interview prompts"
        cross_pack_errors.each { |error| io.puts "     #{error}" }
      end

      io.puts "---"
      valid_pack_count = pack_validity.values.count(true)
      io.puts "#{valid_pack_count}/#{Schema::TARGETS.size} packs valid, #{total_items} items, #{total_cards} cards"
      canonical_packs = Schema::CANONICAL_TARGETS
      invalid_canonical_targets = canonical_packs.reject { |target| pack_validity[target] == true }
      canonical_items = canonical_packs.sum do |target|
        pack = loaded_packs[target]
        pack_validity[target] == true && pack.is_a?(Hash) && pack["items"].is_a?(Array) ? pack["items"].size : 0
      end
      if invalid_canonical_targets.empty?
        io.puts "canonical coverage: #{canonical_packs.size} required packs, #{canonical_items} items; Salesforce is elective"
      else
        io.puts "canonical coverage: INVALID (#{invalid_canonical_targets.join(', ')}); #{canonical_packs.size - invalid_canonical_targets.size}/#{canonical_packs.size} required packs valid, #{canonical_items} items; Salesforce is elective"
      end
      io.puts "content gate: >= #{Schema::PUBLISHABLE_ITEMS_PER_TARGET} items per target"
      io.puts "below publishable bar: #{below_bar.join(", ")}" if below_bar.any?
      failures.zero? && below_bar.empty?
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(EnglishArcade::Validate.call ? 0 : 1)
end
