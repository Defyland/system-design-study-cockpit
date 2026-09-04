# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "english_arcade/schema"
require "english_arcade/text_tools"
require "english_arcade/corpus_index"
require "english_arcade/exercise_factory"
require "english_arcade/exercise_grader"
require "english_arcade/scheduler"

module EnglishArcadeTestSupport
  def canonical_items
    @canonical_items ||= EnglishArcade::Schema::CANONICAL_TARGETS.flat_map do |target|
      path = File.expand_path("../../db/seeds/english_arcade/#{target.tr('_', '-')}.yml", __dir__)
      YAML.safe_load_file(path, aliases: false).fetch("items")
    end
  end

  def sample_item
    canonical_items.find { |item| item.fetch("id") == "golang-01-interface-placement" }
  end

  def factory
    @factory ||= EnglishArcade::ExerciseFactory.new(corpus_index: EnglishArcade::CorpusIndex.new(canonical_items))
  end
end

class Minitest::Test
  include EnglishArcadeTestSupport
end
