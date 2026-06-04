class CreateReviewSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :review_schedules do |t|
      t.references :study_document, null: false, foreign_key: true
      t.references :checkpoint, null: true, foreign_key: true
      t.date :due_on, null: false
      t.integer :interval_days, null: false
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :review_schedules, %i[status due_on]
    add_index :review_schedules, %i[study_document_id checkpoint_id interval_days], name: "idx_review_schedules_document_checkpoint_interval"
  end
end
