require "test_helper"

# Paste is refused only on the fields a student types into. Closed questions have
# no such field, and the teacher's grade form must keep paste for comments.
class PasteGuardTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Quiz", status: :published)
    @short = @exam.questions.create!(
      question_type: :short_text, prompt: "Capital?", points: 1, position: 0, config: {}
    )
    @open = @exam.questions.create!(
      question_type: :open, prompt: "Explain", points: 2, position: 1, config: {}
    )
    @source = @exam.questions.create!(
      question_type: :source, prompt: "Summarize", points: 2, position: 2,
      config: { "source" => "A short passage." }
    )
    @mcq = @exam.questions.create!(
      question_type: :mcq, prompt: "Pick one", points: 1, position: 3,
      config: { "options" => [
        { "id" => "a", "text" => "Paris", "is_correct" => false },
        { "id" => "b", "text" => "Kyiv", "is_correct" => true }
      ] }
    )
    student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: student)
    @attempt = AttemptLifecycle.start!(@assignment)
  end

  test "typed answers refuse paste and closed questions do not" do
    get student_run_path(token: @assignment.access_token)
    assert_response :success

    [ @short, @open, @source ].each do |question|
      field = css_select(%([name="answers[#{question.id}][text]"])).sole

      assert_equal "paste-guard", field["data-controller"]
      assert_includes field["data-action"], "paste->paste-guard#block"
      assert_includes field["data-action"], "drop->paste-guard#block"
      assert_includes field["data-action"], "dragover->paste-guard#block"
    end

    assert_select "[data-controller=paste-guard]", 3
    assert_select "input[type=radio][data-controller=paste-guard]", count: 0
  end

  test "the teacher grade form still accepts paste" do
    sign_in_as @teacher

    get attempt_path(@attempt)
    assert_response :success
    assert_select "[data-controller=paste-guard]", count: 0
  end
end
