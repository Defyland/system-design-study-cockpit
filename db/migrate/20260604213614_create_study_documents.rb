class CreateStudyDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :study_documents do |t|
      t.string :kind, null: false
      t.string :slug, null: false
      t.string :title, null: false
      t.string :source_path, null: false
      t.string :phase
      t.integer :position, null: false, default: 0
      t.text :body_markdown, null: false
      t.string :body_checksum, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :study_documents, %i[kind slug], unique: true
    add_index :study_documents, %i[kind position]
    add_index :study_documents, :body_checksum
  end
end
