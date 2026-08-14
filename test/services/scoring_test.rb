require "test_helper"

class ScoringTest < ActiveSupport::TestCase
  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Quiz", status: :published)
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

  test "ordering scores all or nothing" do
    ordering = create_ordering_question!

    answer = @attempt.answers.create!(question: ordering, payload: { "order" => %w[e1 e2 e3] })
    Scoring.score_ordering!(answer)
    assert_equal 2, answer.reload.auto_score.to_i

    answer.update!(payload: { "order" => %w[e3 e1 e2] })
    Scoring.score_ordering!(answer)
    assert_equal 0, answer.reload.auto_score.to_i
  end

  test "matching scores partial credit" do
    matching = create_matching_question!

    answer = @attempt.answers.create!(
      question: matching,
      payload: { "pairs" => { "l1" => "r1", "l2" => "r2", "l3" => "r1" } }
    )
    Scoring.score_matching!(answer)
    assert_equal 2, answer.reload.auto_score.to_i
  end

  test "ready_to_finalize accepts auto scores for matching and ordering" do
    ordering = create_ordering_question!

    @attempt.answers.create!(question: @mcq, payload: { "option_id" => "b" }, auto_score: 2)
    @attempt.answers.create!(question: @open, payload: { "text" => "Because" }, teacher_score: 2)
    @attempt.answers.create!(question: ordering, payload: { "order" => %w[e1 e2 e3] }, auto_score: 2)

    assert Scoring.ready_to_finalize?(@attempt)
  end

  private

  def create_ordering_question!
    @exam.questions.create!(
      question_type: :ordering,
      prompt: "Order",
      points: 2,
      position: 2,
      config: {
        "items" => [
          { "id" => "e1", "text" => "First" },
          { "id" => "e2", "text" => "Second" },
          { "id" => "e3", "text" => "Third" }
        ]
      }
    )
  end

  def create_matching_question!
    @exam.questions.create!(
      question_type: :matching,
      prompt: "Match",
      points: 3,
      position: 2,
      config: {
        "left" => [
          { "id" => "l1", "text" => "A" },
          { "id" => "l2", "text" => "B" },
          { "id" => "l3", "text" => "C" }
        ],
        "right" => [
          { "id" => "r1", "text" => "1" },
          { "id" => "r2", "text" => "2" },
          { "id" => "r3", "text" => "3" }
        ],
        "pairs" => { "l1" => "r1", "l2" => "r2", "l3" => "r3" }
      }
    )
  end
end
