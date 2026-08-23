# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_23_010300) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "checkpoint_attempts", force: :cascade do |t|
    t.datetime "answered_at", null: false
    t.bigint "checkpoint_id", null: false
    t.string "confidence"
    t.datetime "created_at", null: false
    t.text "decision_sentence"
    t.string "misconception_key"
    t.text "prediction_text"
    t.string "result", null: false
    t.datetime "updated_at", null: false
    t.index ["checkpoint_id", "answered_at"], name: "index_checkpoint_attempts_on_checkpoint_id_and_answered_at"
    t.index ["checkpoint_id"], name: "index_checkpoint_attempts_on_checkpoint_id"
    t.index ["confidence"], name: "index_checkpoint_attempts_on_confidence"
    t.index ["misconception_key"], name: "index_checkpoint_attempts_on_misconception_key"
    t.index ["result"], name: "index_checkpoint_attempts_on_result"
  end

  create_table "checkpoints", force: :cascade do |t|
    t.text "bad_answer"
    t.text "correction"
    t.datetime "created_at", null: false
    t.text "good_answer", null: false
    t.integer "position", null: false
    t.text "prompt", null: false
    t.string "source_label", null: false
    t.bigint "study_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["study_document_id", "position"], name: "index_checkpoints_on_study_document_id_and_position"
    t.index ["study_document_id"], name: "index_checkpoints_on_study_document_id"
  end

  create_table "content_sync_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_count"
    t.text "error_message"
    t.datetime "finished_at"
    t.string "source_location"
    t.string "source_mode", null: false
    t.datetime "started_at", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["finished_at"], name: "index_content_sync_runs_on_finished_at"
    t.index ["started_at"], name: "index_content_sync_runs_on_started_at"
    t.index ["status"], name: "index_content_sync_runs_on_status"
  end

  create_table "english_arcade_attempts", force: :cascade do |t|
    t.string "answer_choice"
    t.datetime "answered_at", null: false
    t.string "attempt_kind", default: "initial", null: false
    t.text "black_box_actual"
    t.text "black_box_expected"
    t.text "black_box_missing_signal"
    t.text "black_box_preventive_rule"
    t.text "black_box_repair"
    t.text "black_box_retest_dates"
    t.text "black_box_root_cause"
    t.text "black_box_symptom"
    t.text "black_box_targeted_exercise"
    t.integer "box_after", default: 1, null: false
    t.integer "box_before", default: 1, null: false
    t.string "card_key", null: false
    t.boolean "correct", null: false
    t.datetime "created_at", null: false
    t.jsonb "diagnostic_evidence", default: {}, null: false
    t.bigint "english_arcade_session_id", null: false
    t.boolean "feedback_revealed", default: false, null: false
    t.text "feynman_text"
    t.string "learner_key", default: "anonymous", null: false
    t.date "next_due_on"
    t.bigint "parent_attempt_id"
    t.text "postmortem_text"
    t.jsonb "prompt_snapshot", default: {}, null: false
    t.integer "quality_score", default: 0, null: false
    t.integer "response_ms"
    t.text "spoken_text"
    t.string "state", default: "committed", null: false
    t.string "target", null: false
    t.text "typed_answer"
    t.datetime "updated_at", null: false
    t.string "variant_key", default: "initial", null: false
    t.index ["attempt_kind"], name: "index_english_arcade_attempts_on_attempt_kind"
    t.index ["correct"], name: "index_english_arcade_attempts_on_correct"
    t.index ["english_arcade_session_id", "created_at"], name: "idx_english_arcade_attempts_session_created"
    t.index ["english_arcade_session_id"], name: "index_english_arcade_attempts_on_english_arcade_session_id"
    t.index ["learner_key", "target", "card_key", "created_at"], name: "idx_english_arcade_attempts_card_history"
    t.index ["learner_key", "target", "card_key", "quality_score", "answered_at"], name: "idx_english_arcade_attempts_mastery"
    t.index ["parent_attempt_id"], name: "index_english_arcade_attempts_on_parent_attempt_id"
    t.index ["state"], name: "index_english_arcade_attempts_on_state"
  end

  create_table "english_arcade_cards", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.integer "box", default: 1, null: false
    t.string "card_key", null: false
    t.integer "correct_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "due_on", null: false
    t.integer "interval_days", default: 1, null: false
    t.datetime "last_answered_at"
    t.boolean "last_correct"
    t.string "learner_key", default: "anonymous", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "target", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_key", "due_on"], name: "idx_english_arcade_cards_due"
    t.index ["learner_key", "target", "card_key"], name: "idx_english_arcade_cards_identity", unique: true
    t.index ["learner_key", "target", "due_on"], name: "idx_english_arcade_cards_target_due"
  end

  create_table "english_arcade_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_seconds", default: 600, null: false
    t.datetime "expires_at"
    t.datetime "finished_at"
    t.string "learner_key", default: "anonymous", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "mode", default: "daily", null: false
    t.integer "question_count", default: 0, null: false
    t.integer "score", default: 0, null: false
    t.datetime "started_at", null: false
    t.string "status", default: "active", null: false
    t.string "target", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_key", "created_at"], name: "idx_english_arcade_sessions_learner_created"
    t.index ["learner_key", "status"], name: "idx_english_arcade_sessions_learner_status"
    t.index ["target"], name: "index_english_arcade_sessions_on_target"
  end

  create_table "learning_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "cue", null: false
    t.text "insight", null: false
    t.bigint "related_document_id"
    t.bigint "study_document_id", null: false
    t.text "unlocks"
    t.datetime "updated_at", null: false
    t.index ["related_document_id"], name: "index_learning_records_on_related_document_id"
    t.index ["study_document_id"], name: "index_learning_records_on_study_document_id"
  end

  create_table "misconception_events", force: :cascade do |t|
    t.text "correction"
    t.datetime "created_at", null: false
    t.string "misconception_key", null: false
    t.text "prompt"
    t.integer "severity", default: 1, null: false
    t.bigint "source_id", null: false
    t.string "source_kind", null: false
    t.bigint "study_document_id"
    t.datetime "updated_at", null: false
    t.index ["misconception_key"], name: "index_misconception_events_on_misconception_key"
    t.index ["severity"], name: "index_misconception_events_on_severity"
    t.index ["source_kind", "source_id"], name: "index_misconception_events_on_source_kind_and_source_id"
    t.index ["study_document_id"], name: "index_misconception_events_on_study_document_id"
  end

  create_table "reminders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.text "message", null: false
    t.integer "priority", default: 1, null: false
    t.datetime "snoozed_until"
    t.string "source_kind", null: false
    t.string "source_slug", null: false
    t.datetime "updated_at", null: false
    t.index ["dismissed_at", "snoozed_until", "priority"], name: "index_reminders_on_dismissed_at_and_snoozed_until_and_priority"
    t.index ["source_kind", "source_slug"], name: "index_reminders_on_source_kind_and_source_slug", unique: true
  end

  create_table "review_schedules", force: :cascade do |t|
    t.bigint "checkpoint_id"
    t.datetime "created_at", null: false
    t.date "due_on", null: false
    t.integer "interval_days", null: false
    t.string "status", default: "pending", null: false
    t.bigint "study_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["checkpoint_id"], name: "index_review_schedules_on_checkpoint_id"
    t.index ["status", "due_on"], name: "index_review_schedules_on_status_and_due_on"
    t.index ["study_document_id", "checkpoint_id", "interval_days", "status"], name: "idx_review_schedules_unique_identity", unique: true
    t.index ["study_document_id"], name: "index_review_schedules_on_study_document_id"
  end

  create_table "simulation_attempts", force: :cascade do |t|
    t.string "confidence"
    t.datetime "created_at", null: false
    t.string "decision", null: false
    t.text "feedback"
    t.jsonb "input_snapshot", default: {}, null: false
    t.string "misconception_key"
    t.jsonb "output_snapshot", default: {}, null: false
    t.string "simulation_slug", null: false
    t.bigint "study_document_id"
    t.datetime "updated_at", null: false
    t.index ["confidence"], name: "index_simulation_attempts_on_confidence"
    t.index ["decision"], name: "index_simulation_attempts_on_decision"
    t.index ["misconception_key"], name: "index_simulation_attempts_on_misconception_key"
    t.index ["simulation_slug"], name: "index_simulation_attempts_on_simulation_slug"
    t.index ["study_document_id"], name: "index_simulation_attempts_on_study_document_id"
  end

  create_table "study_blocks", force: :cascade do |t|
    t.text "content_markdown", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.integer "position", null: false
    t.bigint "study_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["study_document_id", "position"], name: "index_study_blocks_on_study_document_id_and_position", unique: true
    t.index ["study_document_id"], name: "index_study_blocks_on_study_document_id"
  end

  create_table "study_documents", force: :cascade do |t|
    t.string "body_checksum", null: false
    t.text "body_markdown", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "phase"
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.string "source_path", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["body_checksum"], name: "index_study_documents_on_body_checksum"
    t.index ["kind", "position"], name: "index_study_documents_on_kind_and_position"
    t.index ["kind", "slug"], name: "index_study_documents_on_kind_and_slug", unique: true
  end

  create_table "study_missions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "study_document_id", null: false
    t.text "success_signal", null: false
    t.datetime "updated_at", null: false
    t.text "why_now", null: false
    t.index ["study_document_id"], name: "index_study_missions_on_study_document_id", unique: true
  end

  create_table "study_progresses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_block_position", default: 1, null: false
    t.datetime "last_seen_at"
    t.string "status", default: "not_started", null: false
    t.bigint "study_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_study_progresses_on_status"
    t.index ["study_document_id"], name: "index_study_progresses_on_study_document_id", unique: true
  end

  add_foreign_key "checkpoint_attempts", "checkpoints"
  add_foreign_key "checkpoints", "study_documents"
  add_foreign_key "english_arcade_attempts", "english_arcade_attempts", column: "parent_attempt_id"
  add_foreign_key "english_arcade_attempts", "english_arcade_sessions"
  add_foreign_key "learning_records", "study_documents"
  add_foreign_key "learning_records", "study_documents", column: "related_document_id"
  add_foreign_key "misconception_events", "study_documents"
  add_foreign_key "review_schedules", "checkpoints"
  add_foreign_key "review_schedules", "study_documents"
  add_foreign_key "simulation_attempts", "study_documents"
  add_foreign_key "study_blocks", "study_documents"
  add_foreign_key "study_missions", "study_documents"
  add_foreign_key "study_progresses", "study_documents"
end
