class StudyDocument < ApplicationRecord
  KINDS = {
    chapter: "chapter",
    lab: "lab",
    review_card: "review_card",
    capstone: "capstone"
  }.freeze

  enum :kind, KINDS

  has_many :study_blocks, -> { order(:position) }, dependent: :destroy
  has_many :checkpoints, -> { order(:position) }, dependent: :destroy
  has_one :study_progress, dependent: :destroy
  has_many :review_schedules, dependent: :destroy

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
