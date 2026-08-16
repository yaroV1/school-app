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

  test "the finalize control is labelled, not captioned with its own flag value" do
    get attempt_path(@attempt)
    assert_response :success
    # submit_tag lets an options hash overwrite its label argument, so passing
    # value: "1" for the finalize flag rendered a button captioned "1".
    assert_select "button[type=submit][name=finalize][value=?]", "1",
      text: I18n.t("attempts.grade.save_finalize")
  end

  test "submitted attempt hides the live writing hint and opens no subscription" do
    AttemptLifecycle.submit!(@attempt)
    get attempt_path(@attempt)
    assert_response :success
    refute_match I18n.t("attempts.grade.live_hint"), response.body
    # Nothing broadcasts to a finished attempt, so a teacher grading a stack of
    # them should not leave a websocket open per page.
    assert_select "turbo-cable-stream-source", false
  end
end
