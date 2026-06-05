class AddAdaptiveLearningFieldsToAttempts < ActiveRecord::Migration[8.1]
  def change
    change_table :checkpoint_attempts, bulk: true do |t|
      t.text :prediction_text
      t.text :decision_sentence
      t.string :confidence
      t.string :misconception_key
    end

    change_table :simulation_attempts, bulk: true do |t|
      t.string :confidence
      t.string :misconception_key
    end

    add_index :checkpoint_attempts, :confidence
    add_index :checkpoint_attempts, :misconception_key
    add_index :simulation_attempts, :confidence
    add_index :simulation_attempts, :misconception_key
  end
end
