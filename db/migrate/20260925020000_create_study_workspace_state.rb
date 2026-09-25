class CreateStudyWorkspaceState < ActiveRecord::Migration[8.1]
  def change
    add_column :study_card_rounds, :source_ids, :jsonb, default: [], null: false

    create_table :study_card_bookmarks do |t|
      t.string :learner_key, null: false
      t.string :card_key, null: false
      t.timestamps
      t.index %i[learner_key card_key], unique: true
    end

    create_table :study_quiz_rounds do |t|
      t.string :learner_key, null: false
      t.string :topic, null: false
      t.string :mode, null: false, default: "new"
      t.jsonb :card_keys, null: false, default: []
      t.jsonb :responses, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index %i[learner_key updated_at]
    end
  end
end
