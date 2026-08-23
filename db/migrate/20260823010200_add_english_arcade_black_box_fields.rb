class AddEnglishArcadeBlackBoxFields < ActiveRecord::Migration[8.1]
  def change
    change_table :english_arcade_attempts, bulk: true do |t|
      t.text :black_box_symptom
      t.text :black_box_expected
      t.text :black_box_actual
      t.text :black_box_root_cause
      t.text :black_box_repair
    end
  end
end
