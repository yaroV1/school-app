class Scoring
  def self.score_auto!(answer)
    case answer.question.question_type
    when "mcq" then score_mcq!(answer)
    when "ordering" then score_ordering!(answer)
    when "matching" then score_matching!(answer)
    end
  end

  def self.score_all_auto!(attempt)
    attempt.answers.includes(:question).find_each do |answer|
      score_auto!(answer)
    end
  end

  def self.score_mcq!(answer)
    question = answer.question
    return unless question.mcq?

    correct = question.correct_option_id
    answer.update!(auto_score: answer.option_id == correct ? question.points : 0)
  end

  def self.score_ordering!(answer)
    question = answer.question
    return unless question.ordering?

    given = answer.order_ids
    expected = question.correct_order_ids
    answer.update!(auto_score: given == expected ? question.points : 0)
  end

  def self.score_matching!(answer)
    question = answer.question
    return unless question.matching?

    expected = question.pairs
    given = answer.pairs
    if expected.empty?
      answer.update!(auto_score: 0)
      return
    end

    correct = expected.count { |left_id, right_id| given[left_id].to_s == right_id.to_s }
    score = (question.points.to_d * correct / expected.size).round(2)
    answer.update!(auto_score: score)
  end

  def self.ready_to_finalize?(attempt)
    questions = attempt.exam.questions
    answers_by_qid = attempt.answers.reload.index_by(&:question_id)

    questions.all? do |question|
      answer = answers_by_qid[question.id]
      next false unless answer

      if question.auto_gradable?
        answer.auto_score.present? || answer.teacher_score.present?
      else
        answer.teacher_score.present?
      end
    end
  end

  def self.total_for(attempt)
    questions = attempt.exam.questions
    answers_by_qid = attempt.answers.reload.index_by(&:question_id)

    questions.sum do |question|
      answer = answers_by_qid[question.id]
      next 0 unless answer

      answer.effective_score.to_d
    end
  end

  def self.partial_total(attempt)
    attempt.answers.reload.sum { |a| a.effective_score.to_d }
  end
end
