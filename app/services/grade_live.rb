class GradeLive
  def self.replace_answers(attempt, questions: nil)
    new(attempt, questions: questions).replace_answers
  end

  def self.replace_header_and_answers(attempt, questions: nil)
    new(attempt, questions: questions).replace_header_and_answers
  end

  def initialize(attempt, questions: nil)
    @attempt = attempt
    @questions = questions
  end

  def replace_answers
    answers = @attempt.answers.index_by(&:question_id)
    questions.each do |question|
      Turbo::StreamsChannel.broadcast_replace_to(
        @attempt,
        :grade_live,
        target: ActionView::RecordIdentifier.dom_id(question, :student_answer),
        partial: "attempts/student_answer",
        locals: { question: question, answer: answers[question.id] }
      )
    end
  end

  def replace_header_and_answers
    Turbo::StreamsChannel.broadcast_replace_to(
      @attempt,
      :grade_live,
      target: "attempt_live_header",
      partial: "attempts/live_header",
      locals: { attempt: @attempt, exam: exam, grade: @attempt.grade }
    )
    replace_answers
  end

  private

  def questions
    @questions || exam.questions
  end

  def exam
    @attempt.exam
  end
end
