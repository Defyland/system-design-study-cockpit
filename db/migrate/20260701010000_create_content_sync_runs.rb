class CreateContentSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :content_sync_runs do |t|
      t.string :source_mode, null: false
      t.string :source_location
      t.string :status, null: false
      t.integer :document_count
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.text :error_message

      t.timestamps
    end

    add_index :content_sync_runs, :status
    add_index :content_sync_runs, :started_at
    add_index :content_sync_runs, :finished_at
  end
end
