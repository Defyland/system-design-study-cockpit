class ReviewScheduler
  INTERVALS = {
    "revealed" => [ 1 ],
    "correct" => [ 7, 30 ],
    "hesitant" => [ 1, 3, 7, 14 ],
    "missed" => [ 1, 3, 7, 14, 30 ]
  }.freeze

  def self.schedule!(attempt)
    new(attempt).schedule!
  end

  def initialize(attempt)
    @attempt = attempt
    @checkpoint = attempt.checkpoint
    @document = @checkpoint.study_document
  end

  def schedule!
    intervals.each do |days|
      ReviewSchedule.find_or_create_by!(
        study_document: @document,
        checkpoint: @checkpoint,
        interval_days: days,
        status: "pending"
      ) do |schedule|
        schedule.due_on = days.days.from_now.to_date
      end
    end

    create_reminder! if @attempt.hesitant? || @attempt.missed?
  end

  private

  def intervals
    INTERVALS.fetch(@attempt.result)
  end

  def create_reminder!
    message = @checkpoint.bad_answer.presence || @checkpoint.correction.presence || @checkpoint.prompt

    reminder = Reminder.find_or_initialize_by(
      source_kind: "checkpoint",
      source_slug: "#{@document.slug}:#{@checkpoint.id}"
    )
    reminder.assign_attributes(
      message: message,
      priority: [ reminder.priority || 0, @attempt.missed? ? 3 : 2 ].max,
      dismissed_at: nil,
      snoozed_until: nil
    )
    reminder.save!
  end
end
