class MisconceptionEvent < ApplicationRecord
  KEYS = {
    tool_first: "tool_first",
    retry_without_idempotency: "retry_without_idempotency",
    cache_without_freshness: "cache_without_freshness",
    scale_before_delete: "scale_before_delete",
    auth_vs_rate_limit_confusion: "auth_vs_rate_limit_confusion",
    rollback_hesitation: "rollback_hesitation",
    missing_first_metric: "missing_first_metric",
    overgeneralized_big_tech_case: "overgeneralized_big_tech_case"
  }.freeze

  belongs_to :study_document, optional: true

  validates :source_kind, :source_id, :misconception_key, presence: true
  validates :misconception_key, inclusion: { in: KEYS.values }
  validates :severity, numericality: { greater_than: 0 }

  scope :recent, -> { order(created_at: :desc) }
  scope :severe_first, -> { order(severity: :desc, created_at: :desc) }
end
