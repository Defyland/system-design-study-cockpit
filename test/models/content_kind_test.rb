require "test_helper"

class ContentKindTest < ActiveSupport::TestCase
  test "exposes one registry for enum library import and navigation concerns" do
    assert_equal "chapter", ContentKind.enum_mapping.fetch(:chapter)
    assert_equal "side_track_overview", ContentKind.enum_mapping.fetch(:side_track_overview)
    assert_equal "side_track_chapter", ContentKind.enum_mapping.fetch(:side_track_chapter)
    assert_equal "side_track_review_card", ContentKind.enum_mapping.fetch(:side_track_review_card)
    assert_equal "backend_principle", ContentKind.enum_mapping.fetch(:backend_principle)
    assert_equal "engineering_case_study", ContentKind.enum_mapping.fetch(:engineering_case_study)
    assert_equal "operational_playbook", ContentKind.enum_mapping.fetch(:operational_playbook)
    assert_equal "engineering_practice", ContentKind.enum_mapping.fetch(:engineering_practice)
    assert_equal "backend_lab", ContentKind.enum_mapping.fetch(:backend_lab)
    assert_equal "engineering_case_lab", ContentKind.enum_mapping.fetch(:engineering_case_lab)
    assert_equal "Foundations", ContentKind.library_labels.fetch("foundation")
    assert_equal "Side Track References", ContentKind.library_labels.fetch("side_track_reference")
    assert_equal "Side Track Chapters", ContentKind.library_labels.fetch("side_track_chapter")
    assert_equal "Side Track Review Cards", ContentKind.library_labels.fetch("side_track_review_card")
    assert_equal "Backend Principles", ContentKind.library_labels.fetch("backend_principle")
    assert_equal "Engineering Case Studies", ContentKind.library_labels.fetch("engineering_case_study")
    assert_equal "Operational Playbooks", ContentKind.library_labels.fetch("operational_playbook")
    assert_equal "Engineering Practice", ContentKind.library_labels.fetch("engineering_practice")
    assert_equal "Backend Principle Labs", ContentKind.library_labels.fetch("backend_lab")
    assert_equal "Engineering Case Study Labs", ContentKind.library_labels.fetch("engineering_case_lab")
    assert_includes ContentKind.library_keys, "side_track_reference"
    assert_includes ContentKind.library_keys, "side_track_chapter"
    assert_includes ContentKind.library_keys, "side_track_review_card"
    assert_includes ContentKind.library_keys, "decision_contrast"
    assert_includes ContentKind.library_keys, "backend_principle"
    assert_includes ContentKind.library_keys, "engineering_case_study"
    assert_includes ContentKind.library_keys, "operational_playbook"
    assert_includes ContentKind.library_keys, "engineering_practice"
    assert_includes ContentKind.library_keys, "backend_lab"
    assert_includes ContentKind.library_keys, "engineering_case_lab"
    assert_equal "chapters/chapter-*.md", ContentKind.filesystem_patterns.fetch("chapter")
    assert_equal "areas/09-backend-principles/cards/*.md", ContentKind.filesystem_patterns.fetch("backend_principle")
    assert_equal "areas/10-engineering-case-studies/cards/*.md", ContentKind.filesystem_patterns.fetch("engineering_case_study")
    assert_equal "areas/11-operational-playbooks/playbooks/*.md", ContentKind.filesystem_patterns.fetch("operational_playbook")
    assert_equal "areas/12-engineering-practice/cards/*.md", ContentKind.filesystem_patterns.fetch("engineering_practice")
    assert_equal "areas/13-backend-principle-labs/labs/*.md", ContentKind.filesystem_patterns.fetch("backend_lab")
    assert_equal "areas/14-engineering-case-study-labs/labs/*.md", ContentKind.filesystem_patterns.fetch("engineering_case_lab")
    assert_equal "real-world-cases", ContentKind.github_specs.fetch("real_world_case").fetch(:directory)
    assert_equal "areas/09-backend-principles/cards", ContentKind.github_specs.fetch("backend_principle").fetch(:directory)
    assert_equal "areas/10-engineering-case-studies/cards", ContentKind.github_specs.fetch("engineering_case_study").fetch(:directory)
    assert_equal "areas/11-operational-playbooks/playbooks", ContentKind.github_specs.fetch("operational_playbook").fetch(:directory)
    assert_equal "areas/12-engineering-practice/cards", ContentKind.github_specs.fetch("engineering_practice").fetch(:directory)
    assert_equal "areas/13-backend-principle-labs/labs", ContentKind.github_specs.fetch("backend_lab").fetch(:directory)
    assert_equal "areas/14-engineering-case-study-labs/labs", ContentKind.github_specs.fetch("engineering_case_lab").fetch(:directory)
    assert_includes ContentKind.navigation_entries.map(&:key), "ai_system"
    assert_includes ContentKind.navigation_entries.map(&:key), "backend_principle"
    assert_includes ContentKind.navigation_entries.map(&:key), "engineering_case_study"
    assert_includes ContentKind.navigation_entries.map(&:key), "operational_playbook"
    assert_includes ContentKind.navigation_entries.map(&:key), "engineering_practice"
    assert_includes ContentKind.dashboard_keys, "backend_principle"
    assert_includes ContentKind.dashboard_keys, "engineering_case_study"
    assert_includes ContentKind.dashboard_keys, "operational_playbook"
    assert_includes ContentKind.dashboard_keys, "engineering_practice"
    assert_includes ContentKind.dashboard_keys, "backend_lab"
    assert_includes ContentKind.dashboard_keys, "engineering_case_lab"
  end
end
