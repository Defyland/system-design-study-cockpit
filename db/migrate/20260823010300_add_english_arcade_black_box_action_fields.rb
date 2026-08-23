class AddEnglishArcadeBlackBoxActionFields < ActiveRecord::Migration[8.1]
  def change
    change_table :english_arcade_attempts, bulk: true do |t|
      t.text :black_box_missing_signal
      t.text :black_box_preventive_rule
      t.text :black_box_targeted_exercise
      t.text :black_box_retest_dates
    end
  end
end
