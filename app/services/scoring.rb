class Scoring
  def self.score_mcq!(answer)
    question = answer.question
    return unless question.mcq?

    correct = question.correct_option_id
    answer.update!(auto_score: answer.option_id == correct ? question.points : 0)
  end

  def self.score_all_mcq!(attempt)
    attempt.answers.includes(:question).find_each do |answer|
      score_mcq!(answer) if answer.question.mcq?
    end
  end

  def self.ready_to_finalize?(attempt)
    questions = attempt.exam.questions
    answers_by_qid = attempt.answers.reload.index_by(&:question_id)

    questions.all? do |question|
      answer = answers_by_qid[question.id]
      next false unless answer

      if question.mcq?
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

