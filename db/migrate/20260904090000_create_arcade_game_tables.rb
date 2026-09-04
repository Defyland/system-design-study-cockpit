class CreateArcadeGameTables < ActiveRecord::Migration[8.1]
  def change
    create_table :arcade_stage_states do |t|
      t.string :learner_key, null: false, default: "anonymous"
      t.string :target, null: false
      t.string :card_key, null: false
      t.string :stage, null: false
      t.string :status, null: false, default: "new"
      t.decimal :stability, null: false, default: 0, precision: 10, scale: 4
      t.decimal :difficulty, null: false, default: 5, precision: 5, scale: 2
      t.datetime :due_at, null: false
      t.integer :reps, null: false, default: 0
      t.integer :lapses, null: false, default: 0
      t.integer :streak, null: false, default: 0
      t.integer :last_rating
      t.boolean :last_result
      t.datetime :last_reviewed_at
      t.string :content_version, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index %i[learner_key card_key stage], unique: true, name: "idx_arcade_stage_states_identity"
      t.index %i[learner_key status due_at], name: "idx_arcade_stage_states_due"
      t.index %i[learner_key target stage], name: "idx_arcade_stage_states_target_stage"
      t.index %i[learner_key card_key], name: "idx_arcade_stage_states_card"
    end

    create_table :arcade_lessons do |t|
      t.string :learner_key, null: false, default: "anonymous"
      t.string :target_mode, null: false, default: "mixed"
      t.string :target, null: false, default: "mixed"
      t.jsonb :targets, null: false, default: []
      t.string :status, null: false, default: "active"
      t.string :seed, null: false
      t.jsonb :plan, null: false, default: []
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :exercises_total, null: false, default: 0
      t.integer :exercises_done, null: false, default: 0
      t.integer :correct_count, null: false, default: 0
      t.decimal :accuracy, precision: 6, scale: 4
      t.decimal :mastery_delta, precision: 8, scale: 4
      t.integer :new_cards_count, null: false, default: 0
      t.integer :review_count, null: false, default: 0
      t.integer :boss_correct, null: false, default: 0
      t.integer :boss_total, null: false, default: 0
      t.integer :duration_ms
      t.jsonb :summary, null: false, default: {}
      t.timestamps

      t.index %i[learner_key started_at], name: "idx_arcade_lessons_learner_started"
      t.index %i[learner_key status], name: "idx_arcade_lessons_learner_status"
    end

    create_table :arcade_exercise_events do |t|
      t.references :arcade_lesson, null: false, foreign_key: true
      t.string :learner_key, null: false, default: "anonymous"
      t.string :target, null: false
      t.string :card_key, null: false
      t.string :stage, null: false
      t.string :exercise_type, null: false
      t.string :exercise_id, null: false
      t.integer :position, null: false
      t.integer :attempt_no, null: false, default: 1
      t.boolean :boss_round, null: false, default: false
      t.string :reason
      t.boolean :correct, null: false
      t.integer :rating, null: false
      t.integer :self_rating
      t.string :trap_axis
      t.integer :response_ms
      t.jsonb :response, null: false, default: {}
      t.text :response_text
      t.decimal :similarity, precision: 6, scale: 4
      t.integer :anchors_hit
      t.integer :anchors_total
      t.decimal :stability_before, precision: 10, scale: 4
      t.decimal :stability_after, precision: 10, scale: 4
      t.decimal :scheduled_interval_days, precision: 10, scale: 4
      t.decimal :actual_interval_days, precision: 10, scale: 4
      t.decimal :retrievability, precision: 8, scale: 5
      t.datetime :answered_at, null: false
      t.string :content_version, null: false
      t.timestamps

      t.index %i[arcade_lesson_id exercise_id attempt_no], unique: true, name: "idx_arcade_exercise_events_idempotency"
      t.index %i[learner_key answered_at], name: "idx_arcade_exercise_events_learner_answered"
      t.index %i[learner_key card_key stage answered_at], name: "idx_arcade_exercise_events_card_stage_answered"
      t.index %i[learner_key trap_axis answered_at], name: "idx_arcade_exercise_events_axis_answered"
    end
  end
end
