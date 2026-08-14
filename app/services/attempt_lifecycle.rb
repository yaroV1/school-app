class AttemptLifecycle
  class Error < StandardError; end
  class NotAllowed < Error; end
  class Expired < Error; end
  class Conflict < Error; end

  def self.start!(assignment)
    new(assignment).start!
  end

  def self.autosave!(attempt, answers_payload, expected_version: nil)
    new(attempt.assignment).autosave!(attempt, answers_payload, expected_version: expected_version)
  end

  def self.submit!(attempt)
    new(attempt.assignment).submit!(attempt)
  end

  def self.expire_if_needed!(attempt)
    new(attempt.assignment).expire_if_needed!(attempt)
  end

  def initialize(assignment)
    @assignment = assignment
    @exam = assignment.exam
  end

  def start!
    raise NotAllowed, "This link has been revoked" if @assignment.revoked?
    raise NotAllowed, "This test is not open" unless @exam.published?

    if (active = @assignment.in_progress_attempt)
      expire_if_needed!(active)
      return active.reload if active.in_progress?
    end

    unless @exam.within_availability_window?
      case @exam.availability_status
      when :not_yet_open
        raise NotAllowed, "This test is not available yet"
      else
        raise NotAllowed, "This test is no longer available"
      end
    end

    raise NotAllowed, "No attempts remaining" if @assignment.attempts_used >= @exam.max_attempts

    now = Time.current
    deadline = @exam.time_limit_sec.present? ? now + @exam.time_limit_sec.seconds : nil

    @assignment.attempts.create!(
      status: :in_progress,
      attempt_no: @assignment.attempts_used + 1,
      started_at: now,
      deadline_at: deadline,
      last_activity_at: now
    )
  end

  def autosave!(attempt, answers_payload, expected_version: nil)
    expire_if_needed!(attempt)
    raise Expired, "Time is up" if attempt.expired?
    raise NotAllowed, "Attempt is not in progress" unless attempt.in_progress?

    retries = 0
    begin
      Attempt.transaction do
        locked = Attempt.lock.find(attempt.id)
        raise NotAllowed, "Attempt is not in progress" unless locked.in_progress?
        raise Expired, "Time is up" if locked.past_deadline?

        apply_answers!(locked, answers_payload)

        # If client version is stale, reload and re-apply (last-write-wins).
        if expected_version.present? && locked.lock_version != expected_version.to_i
          locked.reload
          raise NotAllowed, "Attempt is not in progress" unless locked.in_progress?
          apply_answers!(locked, answers_payload)
        end

        locked.update!(last_activity_at: Time.current)
      end
    rescue ActiveRecord::StaleObjectError
      retries += 1
      retry if retries < 2
      raise Conflict, "Could not save answers; please try again"
    end

    attempt.reload
  end

  def submit!(attempt)
    expire_if_needed!(attempt)
    raise Expired, "Time is up" if attempt.expired?
    raise NotAllowed, "Attempt is not in progress" unless attempt.in_progress?

    Attempt.transaction do
      locked = Attempt.lock.find(attempt.id)
      raise Expired, "Time is up" if locked.expired? || locked.past_deadline?
      raise NotAllowed, "Attempt is not in progress" unless locked.in_progress?

      Scoring.score_all_mcq!(locked)

      locked.update!(status: :submitted, submitted_at: Time.current, last_activity_at: Time.current)
      grade = locked.grade || locked.build_grade
      grade.max_score = @exam.max_score
      grade.total_score = Scoring.partial_total(locked)
      grade.save!
    end

    attempt.reload
  rescue Expired
    # Ensure expiry is persisted outside a rolled-back submit transaction.
    expire_if_needed!(attempt.reload)
    raise
  end

  def expire_if_needed!(attempt)
    return attempt unless attempt&.in_progress?
    return attempt unless attempt.past_deadline?

    locked = Attempt.lock.find(attempt.id)
    return attempt.reload unless locked.in_progress?
    return attempt.reload unless locked.past_deadline?

    locked.update!(status: :expired, last_activity_at: Time.current)
    grade = locked.grade || locked.build_grade
    grade.max_score = @exam.max_score
    grade.total_score = Scoring.partial_total(locked)
    grade.save!

    attempt.reload
  end

  private

  def apply_answers!(attempt, answers_payload)
    Array(answers_payload).each do |item|
      question_id = item[:question_id] || item["question_id"]
      payload = item[:payload] || item["payload"] || {}
      question = @exam.questions.find(question_id)

      answer = attempt.answers.find_or_initialize_by(question_id: question.id)
      answer.payload = normalize_payload(question, payload)
      answer.save!
      Scoring.score_mcq!(answer) if question.mcq?
    end
  end

  def normalize_payload(question, payload)
    payload = payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload.to_h
    payload = payload.stringify_keys
    if question.mcq?
      { "option_id" => payload["option_id"].to_s.presence }
    else
      { "text" => payload["text"].to_s }
    end
  end
end
