class CreateStudyCardRounds < ActiveRecord::Migration[8.0]
  def change
    create_table :study_card_rounds do |t|
      t.string :learner_key, null: false
      t.string :topic, null: false
      t.boolean :replay, null: false, default: false
      t.jsonb :card_keys, null: false, default: []
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :study_card_rounds, :learner_key
  end
end
