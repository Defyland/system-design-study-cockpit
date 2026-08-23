class AddEnglishArcadeStateMachineFields < ActiveRecord::Migration[8.1]
  def change
    change_table :english_arcade_attempts, bulk: true do |t|
      t.string :state, null: false, default: "committed"
      t.string :variant_key, null: false, default: "initial"
      t.integer :quality_score, null: false, default: 0
      t.text :feynman_text
      t.text :postmortem_text
    end

    add_index :english_arcade_attempts, %i[learner_key target card_key quality_score answered_at], name: "idx_english_arcade_attempts_mastery"
    add_index :english_arcade_attempts, :state
  end
end
