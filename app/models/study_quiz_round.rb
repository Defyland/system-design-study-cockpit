class StudyQuizRound < ApplicationRecord
  scope :for_learner, ->(key) { where(learner_key: key) }

  validates :learner_key, :topic, :mode, presence: true

  def finished?
    position >= card_keys.length
  end

  def current_key
    card_keys[position]
  end

  def self.answered_keys(learner)
    for_learner(learner).where(mode: "new").pluck(:responses).flat_map(&:keys).uniq
  end

  def self.error_keys(learner)
    for_learner(learner).order(:id).pluck(:responses)
      .each_with_object({}) { |responses, result| responses.each { |key, value| result[key] = value["correct"] == false } }
      .select { |_key, wrong| wrong }.keys
  end
end
