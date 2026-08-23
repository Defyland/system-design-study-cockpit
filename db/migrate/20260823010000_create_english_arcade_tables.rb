class CreateEnglishArcadeTables < ActiveRecord::Migration[8.1]
  def change
    create_table :english_arcade_sessions do |t|
      t.string :learner_key, null: false, default: "anonymous"
      t.string :target, null: false
      t.string :mode, null: false, default: "daily"
      t.string :status, null: false, default: "active"
      t.integer :duration_seconds, null: false, default: 600
      t.datetime :started_at, null: false
      t.datetime :expires_at
      t.datetime :finished_at
      t.integer :question_count, null: false, default: 0
      t.integer :score, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index %i[learner_key created_at], name: "idx_english_arcade_sessions_learner_created"
      t.index %i[learner_key status], name: "idx_english_arcade_sessions_learner_status"
      t.index :target
    end

    create_table :english_arcade_cards do |t|
      t.string :learner_key, null: false, default: "anonymous"
      t.string :target, null: false
      t.string :card_key, null: false
      t.integer :box, null: false, default: 1
      t.integer :interval_days, null: false, default: 1
      t.date :due_on, null: false
      t.integer :attempts_count, null: false, default: 0
      t.integer :correct_count, null: false, default: 0
      t.boolean :last_correct
      t.datetime :last_answered_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index %i[learner_key target card_key], unique: true, name: "idx_english_arcade_cards_identity"
      t.index %i[learner_key due_on], name: "idx_english_arcade_cards_due"
      t.index %i[learner_key target due_on], name: "idx_english_arcade_cards_target_due"
    end

    create_table :english_arcade_attempts do |t|
      t.references :english_arcade_session, null: false, foreign_key: true
      t.references :parent_attempt, foreign_key: { to_table: :english_arcade_attempts }
      t.string :learner_key, null: false, default: "anonymous"
      t.string :target, null: false
      t.string :card_key, null: false
      t.string :attempt_kind, null: false, default: "initial"
      t.string :answer_choice
      t.text :typed_answer
      t.text :spoken_text
      t.boolean :correct, null: false
      t.boolean :feedback_revealed, null: false, default: false
      t.integer :response_ms
      t.integer :box_before, null: false, default: 1
      t.integer :box_after, null: false, default: 1
      t.date :next_due_on
      t.datetime :answered_at, null: false
      t.jsonb :diagnostic_evidence, null: false, default: {}
      t.jsonb :prompt_snapshot, null: false, default: {}
      t.timestamps

      t.index %i[english_arcade_session_id created_at], name: "idx_english_arcade_attempts_session_created"
      t.index %i[learner_key target card_key created_at], name: "idx_english_arcade_attempts_card_history"
      t.index :correct
      t.index :attempt_kind
    end
  end
end
