require "test_helper"
require "stringio"
require_relative "../../lib/english_arcade/validate"

class EnglishArcadeCanonicalPackContractTest < ActiveSupport::TestCase
  test "strict production packs clear the twelve-item release bar" do
    output = StringIO.new

    valid = EnglishArcade::Validate.call(
      EnglishArcade::Validate::DEFAULT_DIRECTORY,
      io: output,
      strict: true
    )

    assert valid, output.string
    assert_includes output.string, "8/8 packs valid"
    assert_includes output.string, "content gate: >= 12 items per target"
  rescue Psych::SyntaxError => error
    flunk "canonical production pack is invalid YAML: #{error.message}"
  end
end
