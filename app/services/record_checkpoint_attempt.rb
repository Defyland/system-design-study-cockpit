class RecordCheckpointAttempt
  def self.call(checkpoint:, attributes:)
    new(checkpoint, attributes).call
  end

  def initialize(checkpoint, attributes)
    @checkpoint = checkpoint
    @attributes = attributes
  end

  def call
    CheckpointAttempt.transaction do
      attempt = checkpoint.checkpoint_attempts.create!(attributes)
      ReviewScheduler.schedule!(attempt)
      MisconceptionTracker.record_checkpoint_attempt!(attempt)
      attempt
    end
  end

  private

  attr_reader :checkpoint, :attributes
end
