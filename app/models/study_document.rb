class StudyDocument < ApplicationRecord
  KINDS = ContentKind.enum_mapping.freeze

  enum :kind, KINDS

  has_many :study_blocks, -> { order(:position) }, dependent: :destroy
  has_many :checkpoints, -> { order(:position) }, dependent: :destroy
  has_one :study_progress, dependent: :destroy
  has_many :review_schedules, dependent: :destroy
  has_many :simulation_attempts, dependent: :nullify
  has_many :misconception_events, dependent: :nullify
  has_one :study_mission, dependent: :destroy
  has_many :learning_records, dependent: :destroy
  has_many :related_learning_records, class_name: "LearningRecord", foreign_key: :related_document_id, dependent: :nullify, inverse_of: :related_document

  validates :kind, :slug, :title, :source_path, :body_markdown, :body_checksum, presence: true
  validates :position, numericality: { greater_than_or_equal_to: 0 }
  validates :slug, uniqueness: { scope: :kind }

  scope :ordered, -> { order(:kind, :position, :title) }
  scope :in_study_order, -> { order(:position, :title) }
  scope :for_side_track, ->(side_track_id) { where("metadata ->> 'side_track_id' = ?", side_track_id) }

  def progress
    study_progress || build_study_progress
  end

  def next_checkpoint_after(block_position)
    checkpoints.where("position >= ?", block_position).first
  end

  def side_track_id
    metadata["side_track_id"]
  end
end
