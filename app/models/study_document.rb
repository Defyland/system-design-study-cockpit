class StudyDocument < ApplicationRecord
  KINDS = {
    chapter: "chapter",
    lab: "lab",
    review_card: "review_card",
    capstone: "capstone",
    foundation: "foundation",
    component_card: "component_card",
    simulation_lab: "simulation_lab",
    ai_system: "ai_system",
    real_world_case: "real_world_case",
    decision_contrast: "decision_contrast"
  }.freeze

  enum :kind, KINDS

  has_many :study_blocks, -> { order(:position) }, dependent: :destroy
  has_many :checkpoints, -> { order(:position) }, dependent: :destroy
  has_one :study_progress, dependent: :destroy
  has_many :review_schedules, dependent: :destroy
  has_many :simulation_attempts, dependent: :nullify
  has_many :misconception_events, dependent: :nullify

  validates :kind, :slug, :title, :source_path, :body_markdown, :body_checksum, presence: true
  validates :position, numericality: { greater_than_or_equal_to: 0 }
  validates :slug, uniqueness: { scope: :kind }

  scope :ordered, -> { order(:kind, :position, :title) }
  scope :in_study_order, -> { order(:position, :title) }

  def progress
    study_progress || build_study_progress
  end

  def next_checkpoint_after(block_position)
    checkpoints.where("position >= ?", block_position).first
  end
end
