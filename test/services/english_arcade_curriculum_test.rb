require "test_helper"

class EnglishArcadeCurriculumTest < ActiveSupport::TestCase
  test "has thirty executable days, canonical coverage, and recovery gates" do
    plan = EnglishArcadeCurriculum.plan

    assert_equal 30, plan.length
    assert_equal EnglishArcadeCurriculum::CANONICAL_TARGETS.sort,
      plan.flat_map { |day| day.dig("assignment", "targets") }.uniq.sort
    assert_equal [ 7, 14, 21, 30 ], plan.filter_map { |day| day["gate"] && day["day"] }
    assert plan.all? { |day| day.key?("outcome") && day.key?("assignment") && day.key?("timebox_minutes") }
    assert plan.all? { |day| day.dig("srs_review", "due") && day.dig("reattempt", "required") }
    assert plan.all? { |day| day.dig("follow_up", "required") && day.dig("compression", "required") }
    assert plan.all? { |day| day.fetch("timebox_minutes").between?(60, 90) }
    assert plan.all? { |day| day.dig("assignment", "selector").present? }
    assert plan.first(28).all? { |day| day.dig("assignment", "item_ids").any? }
    assert_equal [ 0, 0 ], plan.last(2).map { |day| day.dig("assignment", "item_ids").length }
    assert plan.select { |day| day["gate"] }.all? { |day| day.dig("gate", "accept").present? && day.dig("gate", "thresholds").present? && day.dig("gate", "recovery").present? }
  end

  test "preserves both required 45-minute method-source mock breakdowns" do
    mocks = EnglishArcadeCurriculum.plan.flat_map { |day| day["mocks"] }
    dsa = mocks.find { |mock| mock["target"] == "dsa" }
    system_design = mocks.find { |mock| mock["target"] == "system_design" }

    assert_equal 45, dsa.fetch("duration_minutes")
    assert_equal 45, system_design.fetch("duration_minutes")
    assert_equal [ 5, 8, 20, 8, 4 ], dsa.fetch("breakdown").map { |(_, minutes)| minutes }
    assert_equal [ 5, 5, 8, 10, 10, 5, 2 ], system_design.fetch("breakdown").map { |(_, minutes)| minutes }
    assert_equal 45, dsa.fetch("breakdown").sum { |(_, minutes)| minutes }
    assert_equal 45, system_design.fetch("breakdown").sum { |(_, minutes)| minutes }
    assert_includes dsa.fetch("constraints"), "pattern <=3m"
    assert_includes dsa.fetch("constraints"), "code <=20m"
  end

  test "six official coding and design mocks have complete distinct phase bundles" do
    phased = EnglishArcadeCurriculum::MOCK_SPECS.select { |spec| %w[dsa system_design].include?(spec.fetch("target")) }
    assert_equal 6, phased.length
    scenario_briefs = EnglishArcadeCurriculum::MOCK_SCENARIO_BRIEFS.values

    phased.each do |spec|
      phases = spec.fetch("phases")
      expected_minutes = spec.fetch("target") == "dsa" ? [ 5, 8, 20, 8, 4 ] : [ 5, 5, 8, 10, 10, 5, 2 ]
      assert_equal expected_minutes, phases.map { |phase| phase.fetch("minutes") }, spec.fetch("id")
      assert_equal phases.length, phases.map { |phase| phase.fetch("id") }.uniq.length
      assert phases.all? { |phase| phase.fetch("brief").length >= 40 && phase.fetch("artifact_prompt").length >= 40 && phase.fetch("minimum_chars") >= 40 }
      own_scenario = EnglishArcadeCurriculum::MOCK_SCENARIO_BRIEFS.fetch(spec.fetch("id"))
      assert phases.all? { |phase| phase.fetch("brief").include?(own_scenario) }, "#{spec.fetch('id')} must carry its own scenario"
      foreign_scenarios = scenario_briefs - [ own_scenario ]
      refute phases.any? { |phase| foreign_scenarios.any? { |scenario| phase.fetch("brief").include?(scenario) } }, "#{spec.fetch('id')} must not carry a foreign scenario"
    end
  end

  test "phase registry exposes a completed state without a phantom sixth or eighth phase" do
    %w[dsa_mock_01 system_design_mock_01].each do |mock_id|
      spec = EnglishArcadeCurriculum.mock(mock_id)
      state = {
        "current_index" => spec.fetch("phases").length,
        "current_phase_started_at" => nil,
        "completed_at" => Time.current.iso8601,
        "checkpoints" => []
      }
      payload = { "phase_index" => spec.fetch("phases").length, "phase_count" => spec.fetch("phases").length, "status" => "complete" }
      assert_equal spec.fetch("phases").length, payload.fetch("phase_index")
      refute_equal payload.fetch("phase_count") + 1, payload.fetch("phase_index")
      refute EnglishArcadeCurriculum.phase_state_valid?(spec, state, session_started_at: Time.current, expires_at: 1.hour.from_now)
    end
  end

  test "phase ledger enforces the exact ninety-percent boundary" do
    phase = EnglishArcadeCurriculum::DSA_PHASES.first
    spec = { "phases" => [ phase ] }
    started_at = Time.utc(2026, 8, 23, 12, 0, 0)
    artifact = "A typed artifact states the contract, invariant, edge case, and verification signal."
    state_at = lambda do |elapsed|
      completed_at = started_at + elapsed
      {
        "current_index" => 1,
        "current_phase_started_at" => nil,
        "completed_at" => completed_at.iso8601(6),
        "checkpoints" => [ {
          "phase_id" => phase.fetch("id"),
          "phase_index" => 0,
          "started_at" => started_at.iso8601(6),
          "completed_at" => completed_at.iso8601(6),
          "elapsed_seconds" => elapsed,
          "artifact" => artifact,
          "artifact_length" => artifact.length
        } ]
      }
    end

    refute EnglishArcadeCurriculum.phase_state_valid?(
      spec,
      state_at.call(269.999),
      session_started_at: started_at,
      expires_at: started_at + 10.minutes,
      now: started_at + 10.minutes
    )
    assert EnglishArcadeCurriculum.phase_state_valid?(
      spec,
      state_at.call(270.0),
      session_started_at: started_at,
      expires_at: started_at + 10.minutes,
      now: started_at + 10.minutes
    )
  end

  test "returns mutable copies without mutating the frozen mock catalogue" do
    copy = EnglishArcadeCurriculum.mock("dsa_mock_01")
    copy.fetch("required_card_keys") << "forged-card"
    copy.fetch("breakdown").first[0].replace("forged phase")

    fresh = EnglishArcadeCurriculum.mock("dsa_mock_01")
    refute_includes fresh.fetch("required_card_keys"), "forged-card"
    assert_equal "clarify and state invariant", fresh.fetch("breakdown").first.first
    assert_equal "clarify and state invariant", EnglishArcadeCurriculum::DSA_BREAKDOWN.first.first
  end

  test "resolves every explicit curriculum item to its assigned canonical target" do
    builder = EnglishArcadeSessionBuilder.new
    EnglishArcadeCurriculum.plan.each do |day|
      targets = day.dig("assignment", "targets")
      day.dig("assignment", "item_ids").each do |item_id|
        target = EnglishArcadeCurriculum.target_for(item_id)
        assert_includes targets, target, "day #{day.fetch('day')} assigns #{item_id}"
        assert builder.card_for(target: target, card_key: item_id), "missing #{item_id}"
      end
    end
    assert_equal EnglishArcadeCurriculum::CANONICAL_TARGETS.sort,
      EnglishArcadeCurriculum.plan.first(2).flat_map { |day| day.dig("assignment", "targets") }.uniq.sort
  end

  test "defines an exact baseline suite and purposefully spaced reattempts" do
    plan = EnglishArcadeCurriculum.plan
    initial_ids = plan.first(2).flat_map { |day| day.dig("assignment", "item_ids") }

    assert_equal EnglishArcadeCurriculum::BASELINE_ITEM_IDS.sort, initial_ids.sort
    assert_equal EnglishArcadeCurriculum::CANONICAL_TARGETS.sort,
      EnglishArcadeCurriculum::BASELINE_ITEM_IDS.map { |item_id| EnglishArcadeCurriculum.target_for(item_id) }.sort

    plan.each do |day|
      day.fetch("spaced_reattempts").each do |reattempt|
        assert_operator day.fetch("day") - reattempt.fetch("original_day"), :>=, 7
        assert_includes %w[retry rephrase follow_up compression], reattempt.fetch("attempt_kind")
        assert EnglishArcadeSessionBuilder.new.card_for(target: EnglishArcadeCurriculum.target_for(reattempt.fetch("item_id")), card_key: reattempt.fetch("item_id"))
      end
    end
  end

  test "makes named mock and assignment requirements cumulative" do
    gates = EnglishArcadeCurriculum.plan.filter_map { |day| day["gate"] }

    assert_equal({ "career" => 1 }, gates[0].fetch("required_mock_counts"))
    assert_equal({ "career" => 1, "dsa" => 1, "rails_experience" => 1 }, gates[1].fetch("required_mock_counts"))
    assert_equal({ "career" => 1, "dsa" => 1, "rails_experience" => 1, "system_design" => 1, "interview" => 1 }, gates[2].fetch("required_mock_counts"))
    assert_equal({ "dsa" => 3, "system_design" => 3, "career" => 1, "rails_experience" => 1, "interview" => 3 }, gates[3].fetch("required_mock_counts"))
    assert_equal [ 6, 12, 18, 26 ], gates.map { |gate| gate.dig("thresholds", "practice_days") }
    assert_equal EnglishArcade::Schema::CANONICAL_TARGETS, EnglishArcadeCurriculum::CANONICAL_TARGETS
    assert_equal %w[gate_d07_career dsa_mock_01 gate_d14_rails_experience system_design_mock_01 gate_d21_go_elixir dsa_mock_02 system_design_mock_02 dsa_mock_03 system_design_mock_03 interview_rehearsal interview_final], EnglishArcadeCurriculum::MOCK_SPECS.map { |spec| spec.fetch("id") }
    assert_equal EnglishArcadeCurriculum.required_mock_ids_through(21), gates[2].dig("thresholds", "required_mock_ids")
    assert_equal EnglishArcadeCurriculum.required_item_ids_through(30), gates[3].dig("thresholds", "required_item_ids")
  end

  test "declares exact cumulative delayed variants and the day thirty target floor" do
    gates = EnglishArcadeCurriculum.plan.filter_map { |day| day["gate"] }

    assert_empty gates[0].dig("thresholds", "required_delayed_item_variant_ids")
    assert_equal EnglishArcadeCurriculum.required_delayed_item_variant_ids_through(14),
      gates[1].dig("thresholds", "required_delayed_item_variant_ids")
    assert_equal 7, gates[1].dig("thresholds", "required_delayed_item_variant_ids").length
    assert_equal EnglishArcadeCurriculum.required_delayed_item_variant_ids_through(21),
      gates[2].dig("thresholds", "required_delayed_item_variant_ids")
    assert_equal EnglishArcadeCurriculum.required_delayed_item_variant_ids_through(20),
      gates[3].dig("thresholds", "required_delayed_item_variant_ids")
    assert_equal EnglishArcadeCurriculum::CANONICAL_TARGETS.to_h { |target| [ target, 2 ] },
      gates[3].dig("thresholds", "critical_target_pair_counts")
  end

  test "schedules every experience item exactly once and reserves final days for mocks" do
    assignments = EnglishArcadeCurriculum.plan.first(28).flat_map { |day| day.dig("assignment", "item_ids") }
    experience_ids = EnglishArcadeCurriculum::EXPERIENCE_ITEM_IDS.values.flatten
    assert_equal experience_ids.sort, assignments.select { |item_id| experience_ids.include?(item_id) }.sort
    assert_equal 56, experience_ids.length
    assert EnglishArcadeCurriculum.plan.last(2).all? { |day| day.fetch("mocks").any? }
    assert EnglishArcadeCurriculum.plan.last(2).all? { |day| day.dig("assignment", "item_ids").empty? }
    assert_equal 3, EnglishArcadeCurriculum.plan.flat_map { |day| day.fetch("mocks") }.count { |mock| mock.fetch("target") == "dsa" }
    assert_equal 3, EnglishArcadeCurriculum.plan.flat_map { |day| day.fetch("mocks") }.count { |mock| mock.fetch("target") == "system_design" }
  end
end
