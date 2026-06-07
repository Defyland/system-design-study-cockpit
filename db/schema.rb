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

ActiveRecord::Schema[8.1].define(version: 2026_06_07_122000) do
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
  add_foreign_key "misconception_events", "study_documents"
  add_foreign_key "review_schedules", "checkpoints"
  add_foreign_key "review_schedules", "study_documents"
  add_foreign_key "simulation_attempts", "study_documents"
  add_foreign_key "study_blocks", "study_documents"
  add_foreign_key "study_progresses", "study_documents"
end
