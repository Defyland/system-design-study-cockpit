# frozen_string_literal: true

require_relative "arcade_test_helper"

class EnglishArcadeCorpusIndexTest < Minitest::Test
  def setup
    @index = EnglishArcade::CorpusIndex.new(canonical_items)
  end

  def test_indexes_target_and_idf
    assert_equal 12, @index.items_for("golang").length
    assert_operator @index.idf("consumer"), :>, @index.idf("the")
  end

  def test_returns_same_length_authored_chip_candidates
    candidates = @index.same_length_candidates(sample_item, length: 2, exclude: [ "consumer package" ])

    assert candidates.length >= 4
    assert candidates.all? { |candidate| EnglishArcade::TextTools.word_count(candidate) == 2 }
    refute_includes candidates.map { |candidate| EnglishArcade::TextTools.normalize(candidate) }, "consumer package"
  end
end
