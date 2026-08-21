require "test_helper"

class StudentResultsTest < ActionDispatch::IntegrationTest
  RUBRIC = "PRIVATE_RUBRIC_SENTINEL".freeze
  MODEL_ANSWER = "PRIVATE_MODEL_ANSWER_SENTINEL".freeze

  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Published results", status: :published, max_attempts: 2)
    create_questions!
    @student = @teacher.students.create!(name: "Marta")
    @assignment = @exam.assignments.create!(student: @student)
    @attempt = submit_attempt!(@assignment, suffix: "FIRST")
  end

  test "teacher controls the result setting and new exams default it off" do
    refute @exam.show_results_to_students?
    sign_in_as @teacher

    patch test_url(@exam), params: { exam: { show_results_to_students: "1" } }

    assert_redirected_to test_url(@exam)
    assert @exam.reload.show_results_to_students?
    get edit_test_url(@exam)
    assert_select "input[name='exam[show_results_to_students]'][type=checkbox][checked]"
  end

  test "result stays hidden until both the setting and teacher finalization allow it" do
    finalize!(@attempt, overall_comment: "FIRST_OVERALL_COMMENT")

    get student_done_url(token: @assignment.access_token)
    assert_result_hidden

    @exam.update!(show_results_to_students: true)
    @attempt.grade.update!(finalized_by_teacher: false, finalized_at: nil)

    get student_done_url(token: @assignment.access_token)
    assert_result_hidden
  end

  test "finalized result shows scores comments and only auto-scored correct answers" do
    @exam.update!(show_results_to_students: true)
    finalize!(@attempt, overall_comment: "OVERALL_FEEDBACK_SENTINEL")

    get student_done_url(token: @assignment.access_token)

    assert_response :success
    assert_select "#student_result"
    assert_match I18n.t("attempts.report.earned", score: "3", max: "9"), response.body
    assert_match "MCQ_TEACHER_COMMENT", response.body
    assert_match "SHORT_TEACHER_COMMENT", response.body
    assert_match "OVERALL_FEEDBACK_SENTINEL", response.body

    assert_select "#correct_answer_question_#{@mcq.id}", text: /RESULT_KEY_KYIV/
    assert_equal [ "RESULT_FIRST", "RESULT_SECOND", "RESULT_THIRD" ],
                 css_select("#correct_answer_question_#{@ordering.id} ol li").map { |node| node.text.strip }
    assert_equal [ "LEFT_ALPHA → RIGHT_TWO", "LEFT_BETA → RIGHT_ONE" ],
                 css_select("#correct_answer_question_#{@matching.id} ul li").map { |node| node.text.squish }
    assert_select "#correct_answer_question_#{@short.id}", false
    assert_select "#correct_answer_question_#{@open.id}", false
    assert_select "#correct_answer_question_#{@source.id}", false

    assert_match "FIRST_SHORT_RESPONSE", response.body
    assert_match "FIRST_OPEN_RESPONSE", response.body
    assert_match "FIRST_SOURCE_RESPONSE", response.body
    refute_match RUBRIC, response.body
    refute_match MODEL_ANSWER, response.body
    refute_match(/is_correct/, response.body)
    refute_match(/&quot;pairs&quot;|"pairs"/, response.body)
  end

  test "disabling results or revoking the assignment immediately hides a published result" do
    @exam.update!(show_results_to_students: true)
    finalize!(@attempt, overall_comment: "HIDE_ME_SENTINEL")

    @exam.update!(show_results_to_students: false)
    get student_done_url(token: @assignment.access_token)
    assert_result_hidden

    @exam.update!(show_results_to_students: true)
    @assignment.revoke!
    get student_done_url(token: @assignment.access_token)
    assert_result_hidden
  end

  test "only the latest finished attempt for the token can be shown" do
    @exam.update!(show_results_to_students: true)
    finalize!(@attempt, overall_comment: "OLDER_ATTEMPT_COMMENT")
    latest = submit_attempt!(@assignment, suffix: "LATEST")

    get student_done_url(token: @assignment.access_token)
    assert_result_hidden

    finalize!(latest, overall_comment: "LATEST_ATTEMPT_COMMENT")
    get student_done_url(token: @assignment.access_token)

    assert_select "#student_result"
    assert_match "LATEST_ATTEMPT_COMMENT", response.body
    assert_match "LATEST_OPEN_RESPONSE", response.body
    refute_match "OLDER_ATTEMPT_COMMENT", response.body
    refute_match "FIRST_OPEN_RESPONSE", response.body
  end

  test "a token cannot select another assignment attempt through parameters" do
    @exam.update!(show_results_to_students: true)
    finalize!(@attempt, overall_comment: "MARTA_PRIVATE_COMMENT")
    other_student = @teacher.students.create!(name: "Oleh")
    other_assignment = @exam.assignments.create!(student: other_student)
    other_attempt = submit_attempt!(other_assignment, suffix: "OTHER")
    finalize!(other_attempt, overall_comment: "OLEH_RESULT_COMMENT")

    get student_done_url(token: other_assignment.access_token, attempt_id: @attempt.id)

    assert_select "#student_result"
    assert_match "OLEH_RESULT_COMMENT", response.body
    assert_match "OTHER_OPEN_RESPONSE", response.body
    refute_match "MARTA_PRIVATE_COMMENT", response.body
    refute_match "FIRST_OPEN_RESPONSE", response.body
  end

  private

  def create_questions!
    @mcq = @exam.questions.create!(
      question_type: :mcq, prompt: "Capital?", points: 1, position: 0,
      config: { "options" => [
        { "id" => "a", "text" => "STUDENT_PARIS", "is_correct" => false },
        { "id" => "b", "text" => "RESULT_KEY_KYIV", "is_correct" => true }
      ] }
    )
    @ordering = @exam.questions.create!(
      question_type: :ordering, prompt: "Order", points: 2, position: 1,
      config: { "items" => [
        { "id" => "o1", "text" => "RESULT_FIRST" },
        { "id" => "o2", "text" => "RESULT_SECOND" },
        { "id" => "o3", "text" => "RESULT_THIRD" }
      ] }
    )
    @matching = @exam.questions.create!(
      question_type: :matching, prompt: "Match", points: 2, position: 2,
      config: {
        "left" => [ { "id" => "l1", "text" => "LEFT_ALPHA" }, { "id" => "l2", "text" => "LEFT_BETA" } ],
        "right" => [ { "id" => "r1", "text" => "RIGHT_ONE" }, { "id" => "r2", "text" => "RIGHT_TWO" } ],
        "pairs" => { "l1" => "r2", "l2" => "r1" }
      }
    )
    @short = @exam.questions.create!(
      question_type: :short_text, prompt: "Short", points: 1, position: 3,
      config: { "rubric" => RUBRIC, "model_answer" => MODEL_ANSWER }
    )
    @open = @exam.questions.create!(
      question_type: :open, prompt: "Open", points: 2, position: 4,
      config: { "rubric" => RUBRIC, "model_answer" => MODEL_ANSWER }
    )
    @source = @exam.questions.create!(
      question_type: :source, prompt: "Source", points: 1, position: 5,
      config: {
        "source" => "PUBLIC_SOURCE_TEXT", "rubric" => RUBRIC, "model_answer" => MODEL_ANSWER
      }
    )
  end

  def submit_attempt!(assignment, suffix:)
    attempt = AttemptLifecycle.start!(assignment)
    AttemptLifecycle.submit!(attempt, answers: [
      { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } },
      { "question_id" => @ordering.id, "payload" => { "order" => %w[o3 o2 o1] } },
      { "question_id" => @matching.id, "payload" => { "pairs" => { "l1" => "r1", "l2" => "r2" } } },
      { "question_id" => @short.id, "payload" => { "text" => "#{suffix}_SHORT_RESPONSE" } },
      { "question_id" => @open.id, "payload" => { "text" => "#{suffix}_OPEN_RESPONSE" } },
      { "question_id" => @source.id, "payload" => { "text" => "#{suffix}_SOURCE_RESPONSE" } }
    ])
    attempt.reload
  end

  def finalize!(attempt, overall_comment:)
    attempt.answers.find_by!(question: @mcq).update!(teacher_comment: "MCQ_TEACHER_COMMENT")
    attempt.answers.find_by!(question: @short).update!(teacher_score: 1, teacher_comment: "SHORT_TEACHER_COMMENT")
    attempt.answers.find_by!(question: @open).update!(teacher_score: 1.5)
    attempt.answers.find_by!(question: @source).update!(teacher_score: 0.5)
    attempt.grade.update!(teacher_comment: overall_comment)
    attempt.grade.finalize!
  end

  def assert_result_hidden
    assert_response :success
    assert_select "#student_result", false
    refute_match "FIRST_OVERALL_COMMENT", response.body
    refute_match "HIDE_ME_SENTINEL", response.body
    refute_match "RESULT_KEY_KYIV", response.body
    refute_match RUBRIC, response.body
    refute_match MODEL_ANSWER, response.body
  end
end
