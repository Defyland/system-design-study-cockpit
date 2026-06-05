class CreateSimulationAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :simulation_attempts do |t|
      t.references :study_document, foreign_key: true
      t.string :simulation_slug, null: false
      t.jsonb :input_snapshot, null: false, default: {}
      t.jsonb :output_snapshot, null: false, default: {}
      t.string :decision, null: false
      t.text :feedback

      t.timestamps
    end

    add_index :simulation_attempts, :simulation_slug
    add_index :simulation_attempts, :decision
  end
end
