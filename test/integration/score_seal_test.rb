require "test_helper"

class ScoreSealTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @exam = create_exam!(@teacher, title: "Quiz", status: :published)
    @exam.questions.create!(
      question_type: :short_text, prompt: "Sky?", points: 2, position: 0, config: {}
    )
    @student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: @student)
    @attempt = AttemptLifecycle.start!(@assignment)
    AttemptLifecycle.submit!(@attempt)
  end

  test "a draft grade is a wet seal and a finalized grade is a fired one" do
    get results_test_path(@exam)
    assert_select "tbody .seal-wet .seal-score", text: "0"
    assert_select "tbody .seal-fired", false

    get student_path(@student)
    assert_select ".data-table .seal-wet"
    assert_select ".data-table .seal-fired", false

    get attempt_path(@attempt)
    assert_select "#attempt_live_header .seal-wet"
    assert_select "#attempt_live_header .seal-fired", false

    @attempt.grade.finalize!

    get results_test_path(@exam)
    assert_select "tbody .seal-fired .seal-score", text: "0"
    assert_select "tbody .seal-wet", false

    get student_path(@student)
    assert_select ".data-table .seal-fired"
    assert_select ".data-table .seal-wet", false

    get attempt_path(@attempt)
    assert_select "#attempt_live_header .seal-fired"
    assert_select "#attempt_live_header .seal-wet", false
  end
end
