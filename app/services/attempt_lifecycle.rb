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
    raise NotAllowed, I18n.t("take.errors.link_revoked") if @assignment.revoked?

    # Resume before the "new start" guards: closing a test or ending its window
    # blocks new attempts only, an attempt already in progress may still finish.
    if (active = @assignment.in_progress_attempt)
      expire_if_needed!(active)
      return active.reload if active.in_progress?
    end

    raise NotAllowed, I18n.t("take.errors.test_not_open") unless @exam.published?

    unless @exam.within_availability_window?
      case @exam.availability_status
      when :not_yet_open
        raise NotAllowed, I18n.t("take.errors.not_available_yet")
      else
        raise NotAllowed, I18n.t("take.errors.no_longer_available")
      end
    end

    raise NotAllowed, I18n.t("take.errors.no_attempts") if @assignment.attempts_used >= @exam.max_attempts

    now = Time.current
    deadline = @exam.time_limit_sec.present? ? now + @exam.time_limit_sec.seconds : nil

    attempt = @assignment.attempts.create!(
      status: :in_progress,
      attempt_no: @assignment.attempts_used + 1,
      started_at: now,
      deadline_at: deadline,
      last_activity_at: now
    )
    LiveBoard.replace(@exam)
    attempt
  end

  def autosave!(attempt, answers_payload, expected_version: nil)
    expire_if_needed!(attempt)
    raise Expired, I18n.t("take.errors.time_up") if attempt.expired?
    raise NotAllowed, I18n.t("take.errors.not_in_progress") unless attempt.in_progress?

    retries = 0
    begin
      Attempt.transaction do
        locked = Attempt.lock.find(attempt.id)
        raise NotAllowed, I18n.t("take.errors.not_in_progress") unless locked.in_progress?
        raise Expired, I18n.t("take.errors.time_up") if locked.past_deadline?

        apply_answers!(locked, answers_payload)

        # If client version is stale, reload and re-apply (last-write-wins).
        if expected_version.present? && locked.lock_version != expected_version.to_i
          locked.reload
          raise NotAllowed, I18n.t("take.errors.not_in_progress") unless locked.in_progress?
          apply_answers!(locked, answers_payload)
        end

        locked.update!(last_activity_at: Time.current)
      end
    rescue ActiveRecord::StaleObjectError
      retries += 1
      retry if retries < 2
      raise Conflict, I18n.t("take.errors.save_conflict")
    end

    attempt.reload
    GradeLive.replace_answers(attempt, questions: @exam.questions)
    attempt
  end

  def submit!(attempt)
    expire_if_needed!(attempt)
    raise Expired, I18n.t("take.errors.time_up") if attempt.expired?
    raise NotAllowed, I18n.t("take.errors.not_in_progress") unless attempt.in_progress?

    Attempt.transaction do
      locked = Attempt.lock.find(attempt.id)
      raise Expired, I18n.t("take.errors.time_up") if locked.expired? || locked.past_deadline?
      raise NotAllowed, I18n.t("take.errors.not_in_progress") unless locked.in_progress?

      Scoring.score_all_auto!(locked)

      locked.update!(status: :submitted, submitted_at: Time.current, last_activity_at: Time.current)
      grade = locked.grade || locked.build_grade
      grade.max_score = @exam.max_score
      grade.total_score = Scoring.partial_total(locked)
      grade.save!
    end

    attempt.reload
    GradeLive.replace_header_and_answers(attempt, questions: @exam.questions)
    LiveBoard.replace(@exam)
    attempt
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
    GradeLive.replace_header_and_answers(attempt, questions: @exam.questions)
    LiveBoard.replace(@exam)
    attempt
  end

  private

  def apply_answers!(attempt, answers_payload)
    questions_by_id = @exam.questions.index_by(&:id)
    answers_by_qid = attempt.answers.index_by(&:question_id)

    Array(answers_payload).each do |item|
      question_id = item[:question_id] || item["question_id"]
      payload = item[:payload] || item["payload"] || {}
      question = questions_by_id[question_id.to_i]
      raise ActiveRecord::RecordNotFound, "Couldn't find Question with 'id'=#{question_id}" unless question

      answer = answers_by_qid[question.id] || attempt.answers.build(question: question)
      answer.question = question
      answer.payload = normalize_payload(question, payload)
      answer.save!
      Scoring.score_auto!(answer)
      answers_by_qid[question.id] = answer
    end
  end

  def normalize_payload(question, payload)
    payload = payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload.to_h
    payload = payload.stringify_keys
    case question.question_type
    when "mcq"
      { "option_id" => payload["option_id"].to_s.presence }
    when "ordering"
      order = payload["order"]
      order = order.values if order.is_a?(Hash)
      { "order" => Array(order).map(&:to_s).reject(&:blank?) }
    when "matching"
      pairs = payload["pairs"] || {}
      pairs = pairs.to_unsafe_h if pairs.respond_to?(:to_unsafe_h)
      {
        "pairs" => pairs.to_h.stringify_keys.transform_values { |value| value.to_s.presence }.compact
      }
    else
      { "text" => payload["text"].to_s }
    end
  end
end
