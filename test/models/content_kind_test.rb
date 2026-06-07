require "test_helper"

class ContentKindTest < ActiveSupport::TestCase
  test "exposes one registry for enum library import and navigation concerns" do
    assert_equal "chapter", ContentKind.enum_mapping.fetch(:chapter)
    assert_equal "backend_principle", ContentKind.enum_mapping.fetch(:backend_principle)
    assert_equal "engineering_case_study", ContentKind.enum_mapping.fetch(:engineering_case_study)
    assert_equal "Foundations", ContentKind.library_labels.fetch("foundation")
    assert_equal "Backend Principles", ContentKind.library_labels.fetch("backend_principle")
    assert_equal "Engineering Case Studies", ContentKind.library_labels.fetch("engineering_case_study")
    assert_includes ContentKind.library_keys, "decision_contrast"
    assert_includes ContentKind.library_keys, "backend_principle"
    assert_includes ContentKind.library_keys, "engineering_case_study"
    assert_equal "chapters/chapter-*.md", ContentKind.filesystem_patterns.fetch("chapter")
    assert_equal "areas/09-backend-principles/cards/*.md", ContentKind.filesystem_patterns.fetch("backend_principle")
    assert_equal "areas/10-engineering-case-studies/cards/*.md", ContentKind.filesystem_patterns.fetch("engineering_case_study")
    assert_equal "real-world-cases", ContentKind.github_specs.fetch("real_world_case").fetch(:directory)
    assert_equal "areas/09-backend-principles/cards", ContentKind.github_specs.fetch("backend_principle").fetch(:directory)
    assert_equal "areas/10-engineering-case-studies/cards", ContentKind.github_specs.fetch("engineering_case_study").fetch(:directory)
    assert_includes ContentKind.navigation_entries.map(&:key), "ai_system"
    assert_includes ContentKind.navigation_entries.map(&:key), "backend_principle"
    assert_includes ContentKind.navigation_entries.map(&:key), "engineering_case_study"
    assert_includes ContentKind.dashboard_keys, "backend_principle"
    assert_includes ContentKind.dashboard_keys, "engineering_case_study"
  end
end
