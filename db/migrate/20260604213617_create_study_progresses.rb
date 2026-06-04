class CreateStudyProgresses < ActiveRecord::Migration[8.1]
  def change
    create_table :study_progresses do |t|
      t.references :study_document, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "not_started"
      t.integer :current_block_position, null: false, default: 1
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :study_progresses, :status
  end
end
