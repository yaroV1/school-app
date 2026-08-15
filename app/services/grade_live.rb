class GradeLive
  include LiveBroadcast

  def self.replace_answers(attempt, questions:)
    new(attempt, questions).replace_answers
  end

  def self.replace_header_and_answers(attempt, questions:)
    new(attempt, questions).replace_header_and_answers
  end

  def initialize(attempt, questions)
    @attempt = attempt
    @questions = questions
  end

  # Only the questions handed in. An untouched question renders the same block
  # it already shows, so broadcasting the whole exam on every autosave is one
  # render and one cable insert per question for nothing.
  def replace_answers
    return if @questions.empty?

    broadcast_safely do
      answers = @attempt.answers.index_by(&:question_id)
      @questions.each do |question|
        Turbo::StreamsChannel.broadcast_replace_to(
          @attempt,
          :grade_live,
          target: ActionView::RecordIdentifier.dom_id(question, :student_answer),
          partial: "attempts/student_answer",
          locals: { question: question, answer: answers[question.id] }
        )
      end
    end
  end

  def replace_header_and_answers
    broadcast_safely do
      Turbo::StreamsChannel.broadcast_replace_to(
        @attempt,
        :grade_live,
        target: "attempt_live_header",
        partial: "attempts/live_header",
        locals: { attempt: @attempt, exam: exam, grade: @attempt.grade }
      )
    end
    replace_answers
  end

  private

  def exam
    @attempt.exam
  end
end
