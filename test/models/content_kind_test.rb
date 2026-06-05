require "test_helper"

class ContentKindTest < ActiveSupport::TestCase
  test "exposes one registry for enum library import and navigation concerns" do
    assert_equal "chapter", ContentKind.enum_mapping.fetch(:chapter)
    assert_equal "Foundations", ContentKind.library_labels.fetch("foundation")
    assert_includes ContentKind.library_keys, "decision_contrast"
    assert_equal "chapters/chapter-*.md", ContentKind.filesystem_patterns.fetch("chapter")
    assert_equal "real-world-cases", ContentKind.github_specs.fetch("real_world_case").fetch(:directory)
    assert_includes ContentKind.navigation_entries.map(&:key), "ai_system"
  end
end
