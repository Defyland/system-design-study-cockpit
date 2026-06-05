class CreateMisconceptionEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :misconception_events do |t|
      t.string :source_kind, null: false
      t.bigint :source_id, null: false
      t.references :study_document, foreign_key: true
      t.string :misconception_key, null: false
      t.text :prompt
      t.text :correction
      t.integer :severity, null: false, default: 1

      t.timestamps
    end

    add_index :misconception_events, [ :source_kind, :source_id ]
    add_index :misconception_events, :misconception_key
    add_index :misconception_events, :severity
  end
end
