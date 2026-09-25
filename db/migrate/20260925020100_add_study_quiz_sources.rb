class AddStudyQuizSources < ActiveRecord::Migration[8.1]
  def change
    add_column :study_quiz_rounds, :source_ids, :jsonb, default: [], null: false
  end
end
