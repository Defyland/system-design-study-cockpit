require "test_helper"

class StudyCardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    StudyCardRound.delete_all
    @learner = ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous"
  end

  test "stale duplicate requests do not advance and another learner cannot update" do
    post study_cards_path, params: { topic: "all", mode: "new" }
    round = StudyCardRound.last
    2.times { patch study_card_path(round), params: { position: 0, card_key: "rippling-this", direction: "next" } }
    assert_equal 1, round.reload.position
    stranger = StudyCardRound.create!(learner_key: "someone-else", topic: "all", card_keys: [ "rippling-this" ])
    patch study_card_path(stranger), params: { position: 0, card_key: "rippling-this", direction: "next" }
    assert_response :not_found
    assert_equal 0, stranger.reload.position
  end

  test "cards completed in a filtered round disappear from an existing mixed round" do
    post study_cards_path, params: { topic: "all", mode: "new" }
    mixed = StudyCardRound.last
    post study_cards_path, params: { topic: "frontend", mode: "new" }
    frontend = StudyCardRound.last
    patch study_card_path(frontend), params: { position: 0, card_key: "rippling-this", direction: "next" }
    get study_card_path(mixed)
    assert_select "[data-card-id='rippling-this']", count: 0
    assert_select "[data-card-id='rippling-bind']", count: 1
    patch study_card_path(mixed), params: { position: 0, card_key: "rippling-this", direction: "next" }
    assert_equal 0, mixed.reload.position, "a stale card must not complete the replacement at the same position"
  end

  test "empty replay and unknown topics never create rounds" do
    assert_no_difference "StudyCardRound.count" do
      post study_cards_path, params: { topic: "all", mode: "replay" }
      assert_redirected_to study_cards_path
      post study_cards_path, params: { topic: "unknown", mode: "new" }
      assert_response :unprocessable_entity
    end
  end
end
