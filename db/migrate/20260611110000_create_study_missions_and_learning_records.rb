class CreateStudyMissionsAndLearningRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :study_missions do |t|
      t.references :study_document, null: false, foreign_key: true, index: { unique: true }
      t.text :why_now, null: false
      t.text :success_signal, null: false

      t.timestamps
    end

    create_table :learning_records do |t|
      t.references :study_document, null: false, foreign_key: true
      t.references :related_document, foreign_key: { to_table: :study_documents }
      t.string :cue, null: false
      t.text :insight, null: false
      t.text :unlocks

      t.timestamps
    end
  end
end
