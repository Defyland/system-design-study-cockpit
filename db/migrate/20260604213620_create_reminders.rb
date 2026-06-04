class CreateReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :reminders do |t|
      t.text :message, null: false
      t.string :source_kind, null: false
      t.string :source_slug, null: false
      t.integer :priority, null: false, default: 1
      t.datetime :snoozed_until
      t.datetime :dismissed_at

      t.timestamps
    end

    add_index :reminders, %i[dismissed_at snoozed_until priority]
    add_index :reminders, %i[source_kind source_slug]
  end
end
