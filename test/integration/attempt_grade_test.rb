require "test_helper"

class AttemptGradeTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher

    @exam = create_exam!(@teacher, title: "Quiz", status: :published)
    @question = @exam.questions.create!(
      question_type: :short_text,
      prompt: "Sky?",
      points: 1,
      position: 0,
      config: {}
    )
    @student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: @student)
    @attempt = AttemptLifecycle.start!(@assignment)
  end

  test "grade page subscribes to live student answers" do
    get attempt_path(@attempt)
    assert_response :success
    assert_select "turbo-cable-stream-source"
    assert_select "#attempt_live_header"
    assert_select "#student_answer_question_#{@question.id}"
    assert_match I18n.t("attempts.grade.live_hint"), response.body
    assert_select "input[name='answers[][teacher_score]']"
  end

  test "submitted attempt hides the live writing hint" do
    AttemptLifecycle.submit!(@attempt)
    get attempt_path(@attempt)
    assert_response :success
    assert_select "turbo-cable-stream-source"
    refute_match I18n.t("attempts.grade.live_hint"), response.body
  end
end
