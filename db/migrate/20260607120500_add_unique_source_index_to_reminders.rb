class AddUniqueSourceIndexToReminders < ActiveRecord::Migration[8.1]
  def up
    deduplicate_reminders!
    remove_index :reminders, name: "index_reminders_on_source_kind_and_source_slug", if_exists: true
    add_index :reminders, %i[source_kind source_slug], unique: true
  end

  def down
    remove_index :reminders, name: "index_reminders_on_source_kind_and_source_slug", if_exists: true
    add_index :reminders, %i[source_kind source_slug]
  end

  private

  def deduplicate_reminders!
    execute <<~SQL.squish
      DELETE FROM reminders
      WHERE id IN (
        SELECT id
        FROM (
          SELECT
            id,
            ROW_NUMBER() OVER (
              PARTITION BY source_kind, source_slug
              ORDER BY priority DESC, updated_at DESC, id DESC
            ) AS duplicate_rank
          FROM reminders
        ) ranked_reminders
        WHERE duplicate_rank > 1
      )
    SQL
  end
end
