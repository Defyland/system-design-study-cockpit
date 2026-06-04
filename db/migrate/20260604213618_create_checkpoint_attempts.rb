class CreateCheckpointAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :checkpoint_attempts do |t|
      t.references :checkpoint, null: false, foreign_key: true
      t.string :result, null: false
      t.datetime :answered_at, null: false

      t.timestamps
    end

    add_index :checkpoint_attempts, %i[checkpoint_id answered_at]
    add_index :checkpoint_attempts, :result
  end
end
