require "test_helper"

class ScoringTest < ActiveSupport::TestCase
  setup do
    @teacher = users(:one)
    @exam = @teacher.exams.create!(title: "Quiz", max_attempts: 1, status: :published)
    @mcq = @exam.questions.create!(
      question_type: :mcq,
      prompt: "2+2?",
      points: 2,
      position: 0,
      config: {
        "options" => [
          { "id" => "a", "text" => "3", "is_correct" => false },
          { "id" => "b", "text" => "4", "is_correct" => true }
        ]
      }
    )
    @open = @exam.questions.create!(
      question_type: :open,
      prompt: "Explain",
      points: 3,
      position: 1,
      config: { "rubric" => "Clear answer" }
    )
    @student = @teacher.students.create!(name: "Ada")
    @assignment = @exam.assignments.create!(student: @student)
    @attempt = @assignment.attempts.create!(
      status: :in_progress,
      attempt_no: 1,
      started_at: Time.current,
      last_activity_at: Time.current
    )
  end

  test "mcq auto score on correct option" do
    answer = @attempt.answers.create!(question: @mcq, payload: { "option_id" => "b" })
    Scoring.score_mcq!(answer)
    assert_equal 2, answer.reload.auto_score.to_i
  end

  test "mcq auto score on wrong option" do
    answer = @attempt.answers.create!(question: @mcq, payload: { "option_id" => "a" })
    Scoring.score_mcq!(answer)
    assert_equal 0, answer.reload.auto_score.to_i
  end

  test "ready_to_finalize requires teacher scores for open answers" do
    @attempt.answers.create!(question: @mcq, payload: { "option_id" => "b" }, auto_score: 2)
    @attempt.answers.create!(question: @open, payload: { "text" => "Because" })

    assert_not Scoring.ready_to_finalize?(@attempt)

    open_answer = @attempt.answers.find_by!(question: @open)
    open_answer.update!(teacher_score: 2)
    assert Scoring.ready_to_finalize?(@attempt)
  end

  test "total_for prefers teacher_score over auto_score" do
    @attempt.answers.create!(question: @mcq, payload: { "option_id" => "b" }, auto_score: 2, teacher_score: 1)
    @attempt.answers.create!(question: @open, payload: { "text" => "Because" }, teacher_score: 3)
    assert_equal 4, Scoring.total_for(@attempt)
  end
end
