class CreateStudyBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :study_blocks do |t|
      t.references :study_document, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :kind, null: false
      t.text :content_markdown, null: false

      t.timestamps
    end

    add_index :study_blocks, %i[study_document_id position], unique: true
  end
end
