class AttemptLifecycle
  class Error < StandardError; end
  class NotAllowed < Error; end
  class Expired < Error; end
  class Conflict < Error; end

  def self.start!(assignment)
    new(assignment).start!
  end

  def self.autosave!(attempt, answers_payload)
    new(attempt.assignment).autosave!(attempt, answers_payload)
  end

  def self.submit!(attempt, answers: nil)
    new(attempt.assignment).submit!(attempt, answers: answers)
  end

  def self.expire_if_needed!(attempt)
    new(attempt.assignment).expire_if_needed!(attempt)
  end

  # Expires a whole scope and refreshes each affected board once. The board
  # partial renders every assignment of the exam, so expiring N attempts one by
  # one used to cost N full board renders.
  def self.expire_overdue!(attempts)
    exams = attempts.filter_map { |attempt| new(attempt.assignment).expire!(attempt) }
    exams.uniq.each { |exam| LiveBoard.replace(exam) }
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

  def autosave!(attempt, answers_payload)
    touched = save_answers!(attempt, answers_payload)
    GradeLive.replace_answers(attempt, questions: touched)
    attempt
  end

  # Writes answers without broadcasting, so a submit that carries the final
  # answers pushes one update instead of one per answer and then another.
  def save_answers!(attempt, answers_payload)
    expire_if_needed!(attempt)
    raise Expired, I18n.t("take.errors.time_up") if attempt.expired?
    raise NotAllowed, I18n.t("take.errors.not_in_progress") unless attempt.in_progress?

    retries = 0
    touched = []
    begin
      Attempt.transaction do
        locked = Attempt.lock.find(attempt.id)
        raise NotAllowed, I18n.t("take.errors.not_in_progress") unless locked.in_progress?
        raise Expired, I18n.t("take.errors.time_up") if locked.past_deadline?

        touched = apply_answers!(locked, answers_payload)
        locked.update!(last_activity_at: Time.current)
      end
    rescue ActiveRecord::StaleObjectError
      retries += 1
      retry if retries < 2
      raise Conflict, I18n.t("take.errors.save_conflict")
    end

    attempt.reload
    touched
  end

  def submit!(attempt, answers: nil)
    save_answers!(attempt, answers) if answers.present?

    expire_if_needed!(attempt)
    raise Expired, I18n.t("take.errors.time_up") if attempt.expired?
    raise NotAllowed, I18n.t("take.errors.not_in_progress") unless attempt.in_progress?

    begin
      Attempt.transaction do
        locked = Attempt.lock.find(attempt.id)
        raise Expired, I18n.t("take.errors.time_up") if locked.expired? || locked.past_deadline?
        raise NotAllowed, I18n.t("take.errors.not_in_progress") unless locked.in_progress?

        Scoring.score_all_auto!(locked)

        locked.update!(status: :submitted, submitted_at: Time.current, last_activity_at: Time.current)
        refresh_grade!(locked)
      end
    rescue ActiveRecord::StaleObjectError
      # Deliberately no retry: save_answers! owns the retry policy, and a collision anywhere in
      # this transaction means something else already moved this attempt.
      raise Conflict, I18n.t("take.errors.save_conflict")
    end

    attempt.reload
    GradeLive.replace_header_and_answers(attempt, questions: answered_questions(attempt))
    LiveBoard.replace(@exam)
    attempt
  rescue Expired
    # Ensure expiry is persisted outside a rolled-back submit transaction.
    expire_if_needed!(attempt.reload)
    raise
  end

  def expire_if_needed!(attempt)
    LiveBoard.replace(@exam) if expire!(attempt)
    attempt
  end

  # Returns the exam when this call is what expired the attempt, nil otherwise,
  # so a caller sweeping many attempts can refresh the board once at the end.
  def expire!(attempt)
    return unless attempt&.in_progress?
    return unless attempt.past_deadline?

    locked = Attempt.lock.find(attempt.id)
    unless locked.in_progress? && locked.past_deadline?
      attempt.reload
      return
    end

    locked.update!(status: :expired, last_activity_at: Time.current)
    refresh_grade!(locked)

    attempt.reload
    GradeLive.replace_header_and_answers(attempt, questions: answered_questions(attempt))
    @exam
  end

  private

  # A teacher who has already signed off keeps their total. Submitting or
  # expiring must not silently move a grade the teacher finalized.
  def refresh_grade!(attempt)
    grade = attempt.grade || attempt.build_grade
    return grade if grade.finalized_by_teacher?

    grade.max_score = @exam.max_score
    grade.total_score = Scoring.partial_total(attempt)
    grade.save!
    grade
  end

  # Questions the student actually answered. The rest render an unchanged
  # "no answer" block, so there is nothing to push for them.
  def answered_questions(attempt)
    answered_ids = attempt.answers.map(&:question_id).to_set
    @exam.questions.select { |question| answered_ids.include?(question.id) }
  end

  # Returns only the questions whose answer actually moved. The runner posts the
  # whole form every few seconds, so returning everything it sent would rebroadcast
  # every question on a timer and redraw blocks under the teacher's cursor.
  def apply_answers!(attempt, answers_payload)
    questions_by_id = @exam.questions.index_by(&:id)
    answers_by_qid = attempt.answers.index_by(&:question_id)

    Array(answers_payload).filter_map do |item|
      question_id = item[:question_id] || item["question_id"]
      payload = item[:payload] || item["payload"] || {}
      question = questions_by_id[question_id.to_i]
      raise ActiveRecord::RecordNotFound, "Couldn't find Question with 'id'=#{question_id}" unless question

      answer = answers_by_qid[question.id] || attempt.answers.build(question: question)
      answer.question = question
      answer.payload = normalize_payload(question, payload)
      # A first answer counts as a change: the page swaps "no answer" for a real block.
      rewritten = answer.new_record? || answer.payload_changed?
      answer.save!
      Scoring.score_auto!(answer)
      answers_by_qid[question.id] = answer
      question if rewritten || answer.saved_change_to_auto_score?
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
