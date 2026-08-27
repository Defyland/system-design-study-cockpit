# frozen_string_literal: true

require "test_helper"
require "open3"
require "yaml"

class EnglishArcadeExperienceProvenanceTest < ActiveSupport::TestCase
  TARGETS = %w[career rails_experience go_experience elixir_experience].freeze
  ITEM_COUNTS = { "career" => 12, "rails_experience" => 20, "go_experience" => 12, "elixir_experience" => 12 }.freeze
  PORTFOLIO_CLASSES = %w[portfolio_code public_challenge deployed_personal_project].freeze
  FORBIDDEN_SAFE_CLAIMS = /\b(employer|production|customers?|on-call|business results?|production-scale performance)\b/i

  test "experience packs are complete, unique, and carry complete provenance" do
    TARGETS.each do |target|
      pack = load_pack(target)
      items = pack.fetch("items")
      assert_equal ITEM_COUNTS.fetch(target), items.size
      %w[id prompt best_answer feedback].each do |field|
        assert_equal items.size, items.map { |item| item.fetch(field) }.uniq.size, "#{target} #{field} must be unique"
      end
      assert_equal 3, pack.fetch("cards").size
      items.each { |item| assert_provenance(item, target) }
    end
  end

  test "approved career pack has distinct interview coaching and no rejected boilerplate" do
    items = load_pack("career").fetch("items")
    introductory_answers = items.first(4).map { |item| item.fetch("best_answer") }
    assert_operator introductory_answers.first.split.size, :>=, 110
    assert_operator introductory_answers.first.split.size, :<=, 160
    assert_operator introductory_answers[3].split.size, :>=, 80
    assert_operator introductory_answers[3].split.size, :<=, 130
    introductory_answers.each do |answer|
      refute_match(/\b(?:story bank|preparation material|experience material)\b/i, answer)
    end
    career_one_answer = introductory_answers.first
    refute_match(/\bI\s+(?:built|implemented|operated)\b/i, career_one_answer)
    refute_match(/\bmy\s+(?:Go|Elixir)(?:\s*(?:\/|and)\s*(?:Go|Elixir))?\s+portfolio\b/i, career_one_answer)
    visible = {
      "context" => items.map { |item| item.fetch("context") },
      "distractors" => items.flat_map { |item| item.fetch("distractors").map { |d| d.fetch("text") } },
      "follow_up" => items.map { |item| item.fetch("follow_up") },
      "compression" => items.map { |item| item.fetch("compression") },
      "rephrase" => items.map { |item| item.fetch("rephrase").fetch("prompt") },
      "feynman" => items.map { |item| item.fetch("feynman") },
      "black_box" => items.map { |item| item.fetch("black_box") }
    }
    visible.each { |name, values| assert_equal values.size, values.uniq.size, "career #{name} must be item-specific" }
    EnglishArcade::Schema::LANGUAGE_AXES.each do |axis|
      values = items.map { |item| item.fetch("feedback").fetch(axis) }
      assert_equal values.size, values.uniq.size, "career feedback #{axis} must be item-specific"
    end
    diagnoses = items.flat_map { |item| item.fetch("distractors").map { |distractor| distractor.fetch("why_wrong") } }
    assert_equal 24, diagnoses.uniq.size, "career distractor diagnoses must be item-specific"
    distractors = items.flat_map { |item| item.fetch("distractors") }
    texts = distractors.map { |distractor| distractor.fetch("text") }
    assert_equal 24, texts.uniq.size, "career distractor texts must be item-specific"
    texts.each do |text|
      assert_operator text.split.size, :<=, 55, "career distractors must stay candidate-length"
      refute_match(/\b(that would|the mistake|credible answer|interviewer is testing|supporting artefact)\b/i, text)
    end
    feedback = items.flat_map do |item|
      EnglishArcade::Schema::LANGUAGE_AXES.map { |axis| item.fetch("feedback").fetch(axis) }
    end
    assert_equal 60, feedback.uniq.size, "career feedback must be specific to its item and axis"
    feedback.each do |value|
      refute_match(/\A(?:Use a measured|Be careful only|Lead with|Keep the actor|End with)\b/i, value)
    end
    items.each do |item|
      sentences = EnglishArcade::Schema::LANGUAGE_AXES.flat_map do |axis|
        item.fetch("feedback").fetch(axis).split(/(?<=[.!?])\s+/)
      end
      assert_equal sentences.size, sentences.uniq.size, "#{item.fetch('id')} feedback axes must not share a sentence"
    end
    black_box_fields = %w[symptom expected actual root_cause repair]
    black_box_fields.each do |field|
      values = items.map { |item| item.fetch("black_box").fetch(field) }
      assert_equal 12, values.uniq.size, "career black_box #{field} must be item-specific"
      values.each do |value|
        refute_match(/\A(?:A listener-specific answer|A generic response|The response was shaped|Return to)\b/i, value)
      end
    end
    safe_versions = items.map { |item| item.fetch("provenance").fetch("safe_interview_version") }
    assert_equal 12, safe_versions.uniq.size, "career safe interview versions must be item-specific"
    safe_versions.each do |version|
      refute_match(/Career answer \d+:/i, version)
      refute_match(/\AI would (organize the answer|use one fixed story)/i, version)
    end
    items.each do |item|
      claims = item.fetch("provenance").fetch("files").map { |file| file.fetch("claim") }.join(" ")
      refute_match /supports .*résumé-derived interview topic/i, claims
    end
    rejected = [
      /The distinct example here is/i,
      /concrete failure boundary and the check/i,
      /familiar shortcut without the boundary/i,
      /It would sound confident/i,
      /For this item:/i,
      /What would the interviewer ask next if/i,
      /Compress .* into a single careful sentence/i,
      /The judgment behind/i,
      /The (a|an) /i
    ]
    rejected.each do |pattern|
      refute items.to_s.match?(pattern), "career contains rejected boilerplate #{pattern.inspect}"
    end
  end

  test "career mixed-evidence introductions cite Rails, Go, and Elixir artifacts" do
    expected = {
      "system-design-estudos/interview/story-bank/01-ruby-rails-backend-story-bank.md" => "716a7d9",
      "fulfillhub-go-commerce-platform/README.md" => "3bc2b641d17bd93ba151ff78441d9bf190f0fc07",
      "pulseops-elixir-job-platform/README.md" => "f1330d0588d1b46253abb18a3c4c1ec6869152b6"
    }
    items = load_pack("career").fetch("items").index_by { |item| item.fetch("id") }
    %w[career-01-a-60-to-90-second-introduction career-03-an-engineering-introduction].each do |id|
      provenance = items.fetch(id).fetch("provenance")
      assert_equal "backend-challenges", provenance.fetch("repository")
      files = provenance.fetch("files").index_by { |file| file.fetch("path") }
      assert_equal expected.keys.sort, files.keys.sort
      expected.each do |path, sha|
        assert_equal sha, files.fetch(path).fetch("commit")
        assert file_exists_at_commit?("backend-challenges", path, sha), "#{id}: #{path}@#{sha}"
      end
    end
  end

  private

  def load_pack(target)
    YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{target.tr('_', '-')}.yml"), aliases: false)
  end

  def assert_provenance(item, target)
    provenance = item.fetch("provenance")
    assert_includes EnglishArcade::Schema::EVIDENCE_CLASSES, provenance.fetch("evidence_class")
    assert provenance.fetch("verified_claims").any?
    assert_operator provenance.fetch("safe_interview_version").length, :>=, 80
    paths = [ item.fetch("sources"), provenance.fetch("files") ].flatten.map { |value| value.is_a?(Hash) ? value["path"] : value }
    paths.compact.each do |evidence_path|
      refute EnglishArcade::PackValidator.sensitive_evidence_path?(evidence_path), evidence_path
    end
    provenance.fetch("files").each do |file|
      refute_match %r{\A/|\.\.}, file.fetch("path")
      assert_match /\A[0-9a-f]{7,64}\z/, file.fetch("commit")
      assert File.file?(source_file(provenance.fetch("repository"), file.fetch("path"))), file.fetch("path")
      assert file_exists_at_commit?(provenance.fetch("repository"), file.fetch("path"), file.fetch("commit")), file.inspect
    end
    if provenance.fetch("evidence_class") == "resume_derived"
      confirmation = provenance.fetch("confirmation_required").join(" ").downcase
      %w[resume pdf absent ownership metrics mechanisms].each { |word| assert_includes confirmation, word }
    end
    return unless PORTFOLIO_CLASSES.include?(provenance.fetch("evidence_class"))

    safe = provenance.fetch("safe_interview_version")
    refute_match FORBIDDEN_SAFE_CLAIMS, safe
    if provenance.fetch("evidence_class") == "deployed_personal_project"
      assert_match /personal (project|product)/i, safe
    else
      assert_match /\b(portfolio|study|challenge)\b/i, safe
    end
  end

  def source_file(repository, relative_path)
    repository == "system-design-estudos" ? Rails.root.parent.join(repository, relative_path) : Rails.root.parent.join(relative_path)
  end

  def file_exists_at_commit?(repository, relative_path, sha)
    repo = repository == "system-design-estudos" ? Rails.root.parent.join(repository) : Rails.root.parent.join(relative_path.split("/").first)
    path_in_repo = repository == "system-design-estudos" ? relative_path : relative_path.split("/", 2).last
    _stdout, _stderr, status = Open3.capture3("git", "-C", repo.to_s, "cat-file", "-e", "#{sha}:#{path_in_repo}")
    status.success?
  end
end
