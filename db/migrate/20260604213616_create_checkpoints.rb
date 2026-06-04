class CreateCheckpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :checkpoints do |t|
      t.references :study_document, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :source_label, null: false
      t.text :prompt, null: false
      t.text :good_answer, null: false
      t.text :bad_answer
      t.text :correction

      t.timestamps
    end

    add_index :checkpoints, %i[study_document_id position]
  end
end
