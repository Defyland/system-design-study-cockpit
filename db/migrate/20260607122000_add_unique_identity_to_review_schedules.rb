class AddUniqueIdentityToReviewSchedules < ActiveRecord::Migration[8.1]
  def up
    deduplicate_review_schedules!
    remove_index :review_schedules, name: "idx_review_schedules_document_checkpoint_interval", if_exists: true
    add_index :review_schedules,
      %i[study_document_id checkpoint_id interval_days status],
      unique: true,
      name: "idx_review_schedules_unique_identity"
  end

  def down
    remove_index :review_schedules, name: "idx_review_schedules_unique_identity", if_exists: true
    add_index :review_schedules,
      %i[study_document_id checkpoint_id interval_days],
      name: "idx_review_schedules_document_checkpoint_interval"
  end

  private

  def deduplicate_review_schedules!
    execute <<~SQL.squish
      DELETE FROM review_schedules
      WHERE id IN (
        SELECT id
        FROM (
          SELECT
            id,
            ROW_NUMBER() OVER (
              PARTITION BY study_document_id, checkpoint_id, interval_days, status
              ORDER BY due_on ASC, updated_at DESC, id DESC
            ) AS duplicate_rank
          FROM review_schedules
        ) ranked_review_schedules
        WHERE duplicate_rank > 1
      )
    SQL
  end
end
