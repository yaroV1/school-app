require "test_helper"

# The ledger is append-only and the award is per assignment, so every case here is really the
# same question: after this finalization, does the sum of the assignment's entries equal what
# the student's best finalized grade is worth?
class CreditsTest < ActiveSupport::TestCase
  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Quiz", status: :published, max_attempts: 2)
    @question = @exam.questions.create!(
      question_type: :open, prompt: "Explain", points: 10, position: 0, config: {}
    )
    @student = @teacher.students.create!(name: "Ada")
    @assignment = @exam.assignments.create!(student: @student)
  end

  test "a finalized grade awards credits in proportion to the score" do
    finalize_attempt!(score: 7)

    assert_equal 7, @student.credit_balance
    assert_equal [ 7 ], @assignment.credit_entries.pluck(:amount)
  end

  test "a perfect score awards the full rate and a blank one awards nothing" do
    finalize_attempt!(score: 10)
    assert_equal Credits::PER_TEST, @student.credit_balance

    other = @exam.assignments.create!(student: @teacher.students.create!(name: "Bo"))
    finalize_attempt!(score: 0, assignment: other)
    assert_equal 0, other.student.credit_balance
  end

  test "the share is rounded, not truncated" do
    # 2/3 of ten is 6.67: truncation would pay 6.
    assert_equal 7, Credits.credits_for(Grade.new(max_score: 3, total_score: 2))
  end

  test "a teacher score above the question points cannot pay more than the full rate" do
    finalize_attempt!(score: 25)

    assert_equal Credits::PER_TEST, @student.credit_balance
  end

  test "a test worth no points awards nothing instead of dividing by zero" do
    grade = Grade.new(max_score: 0, total_score: 0)

    assert_equal 0, Credits.credits_for(grade)
  end

  test "re-finalizing an unchanged grade appends nothing" do
    attempt = finalize_attempt!(score: 7)

    attempt.grade.finalize!

    assert_equal 7, @student.credit_balance
    assert_equal 1, @assignment.credit_entries.count
  end

  test "a better retake appends only the improvement" do
    finalize_attempt!(score: 4)
    finalize_attempt!(score: 9, attempt_no: 2)

    assert_equal 9, @student.credit_balance
    assert_equal [ 4, 5 ], @assignment.credit_entries.order(:id).pluck(:amount)
  end

  test "a worse retake leaves the balance alone" do
    finalize_attempt!(score: 9)
    finalize_attempt!(score: 3, attempt_no: 2)

    assert_equal 9, @student.credit_balance
    assert_equal 1, @assignment.credit_entries.count
  end

  test "lowering a finalized score appends a negative correction" do
    attempt = finalize_attempt!(score: 9)

    attempt.answers.first.update!(teacher_score: 5)
    attempt.grade.finalize!

    assert_equal 5, @student.credit_balance
    assert_equal [ 9, -4 ], @assignment.credit_entries.order(:id).pluck(:amount)
  end

  test "lowering the best of two attempts falls back to the other, never below zero" do
    first = finalize_attempt!(score: 6)
    second = finalize_attempt!(score: 9, attempt_no: 2)

    second.answers.first.update!(teacher_score: 1)
    second.grade.finalize!

    assert_equal 6, @student.credit_balance, "the untouched first attempt is now the best"
    assert_equal 6, Credits.target_for(@assignment)
    assert_operator @student.credit_balance, :>=, 0
    assert_equal first.grade.total_score.to_i, 6
  end

  private

  def finalize_attempt!(score:, assignment: @assignment, attempt_no: 1)
    attempt = assignment.attempts.create!(
      status: :submitted,
      attempt_no: attempt_no,
      started_at: Time.current,
      last_activity_at: Time.current,
      submitted_at: Time.current
    )
    question = assignment.exam.questions.first
    attempt.answers.create!(question: question, payload: { "text" => "x" }, teacher_score: score)
    attempt.create_grade!(max_score: assignment.exam.max_score)
    attempt.grade.finalize!
    attempt
  end
end
