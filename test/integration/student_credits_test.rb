require "test_helper"

# Credits are the one number a student carries between tests, so both sides of the wall get
# their own assertions here: what the teacher may inspect, and what the unauthenticated
# `/t/:token` pages are allowed to say about it.
class StudentCreditsTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Дроби", status: :published)
    @question = @exam.questions.create!(
      question_type: :open, prompt: "Explain", points: 10, position: 0, config: {}
    )
    @student = @teacher.students.create!(name: "Ada")
    @assignment = @exam.assignments.create!(student: @student)
  end

  test "the teacher sees the balance and the test each award came from" do
    finalize!(score: 7)
    sign_in_as @teacher

    get student_path(@student)
    assert_response :success

    assert_match I18n.t("common.credits", count: 7), response.body
    row = css_select(".data-table tbody tr").last.text.squish
    assert_match "Дроби", row
    assert_match "+7", row
  end

  test "a student with no finalized work shows an empty balance and no awards" do
    sign_in_as @teacher

    get student_path(@student)
    assert_response :success

    assert_match I18n.t("common.credits", count: 0), response.body
    assert_match I18n.t("students.credits.empty"), response.body
  end

  test "a correction is listed as its own negative row" do
    attempt = finalize!(score: 9)
    attempt.answers.first.update!(teacher_score: 5)
    attempt.grade.finalize!
    sign_in_as @teacher

    get student_path(@student)
    assert_response :success

    amounts = css_select(".data-table tbody tr td.num").map { |cell| cell.text.strip }
    assert_includes amounts, "+9"
    assert_includes amounts, "-4"
    assert_match I18n.t("common.credits", count: 5), response.body
  end

  test "another teacher cannot reach the balance" do
    finalize!(score: 7)
    sign_in_as users(:two)

    get student_path(@student)
    assert_response :not_found
  end

  private

  def finalize!(score:)
    attempt = @assignment.attempts.create!(
      status: :submitted,
      attempt_no: @assignment.attempts.count + 1,
      started_at: Time.current,
      last_activity_at: Time.current,
      submitted_at: Time.current
    )
    attempt.answers.create!(question: @question, payload: { "text" => "x" }, teacher_score: score)
    attempt.create_grade!(max_score: @exam.max_score)
    attempt.grade.finalize!
    attempt
  end
end
