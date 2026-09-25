class StudyCardRound < ApplicationRecord
  scope :for_learner, ->(key) { where(learner_key: key) }

  def self.completed_keys(learner)
    for_learner(learner).where(replay: false).pluck(:card_keys, :position)
      .flat_map { |keys, position| keys.take(position) }.uniq
  end

  def remove_completed_cards!
    return if replay?

    with_lock do
      completed_elsewhere = self.class.completed_keys(learner_key)
      remaining = card_keys.drop(position) - completed_elsewhere
      update!(card_keys: card_keys.take(position) + remaining) if remaining != card_keys.drop(position)
    end
  end

  def finished?
    position >= card_keys.length
  end
end
