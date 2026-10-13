require "test_helper"

# Two browsers on one /t/:token link: each `open_session` keeps its own cookie jar, which is the
# whole of what tells them apart.
class DeviceBindingTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Quiz", status: :published, time_limit_sec: 600, max_attempts: 2)
    @question = @exam.questions.create!(
      question_type: :mcq, prompt: "Capital?", points: 1, position: 0,
      config: { "options" => [
        { "id" => "a", "text" => "Paris", "is_correct" => false },
        { "id" => "b", "text" => "Kyiv", "is_correct" => true }
      ] }
    )
    @student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: @student)
    @token = @assignment.access_token

    @owner = open_session
    @other = open_session
  end

  def start_in(browser)
    browser.post student_start_path(token: @token)
    @assignment.attempts.in_progress.sole
  end

  def autosave_in(browser, attempt)
    browser.put student_answers_path(token: @token),
                params: { attempt_id: attempt.id, answers: [ { question_id: @question.id, payload: { option_id: "a" } } ] },
                as: :json
  end

  test "the browser that started the test can come back to it" do
    attempt = start_in(@owner)
    device_cookie = Array(@owner.response.headers["Set-Cookie"]).flat_map { |line| line.split("\n") }
                                                                 .find { |line| line.start_with?("take_device=") }
    assert_match(/httponly/i, device_cookie)

    @owner.get student_portal_path(token: @token)
    @owner.assert_select "form[action=?]", student_start_path(token: @token)

    @owner.post student_start_path(token: @token)
    @owner.assert_redirected_to student_run_path(token: @token)
    assert_equal attempt, @assignment.attempts.in_progress.sole

    @owner.get student_run_path(token: @token)
    @owner.assert_response :success
  end

  test "another browser cannot start, open, save, submit or report on the started test" do
    attempt = start_in(@owner)

    @other.get student_portal_path(token: @token)
    @other.assert_response :success
    @other.assert_select "form[action=?]", student_start_path(token: @token), false
    @other.assert_select ".flash-alert", text: I18n.t("take.errors.other_device")

    @other.post student_start_path(token: @token)
    @other.assert_redirected_to student_portal_path(token: @token)
    assert_equal I18n.t("take.errors.other_device"), @other.flash[:alert]

    @other.get student_run_path(token: @token)
    @other.assert_redirected_to student_portal_path(token: @token)

    autosave_in(@other, attempt)
    @other.assert_response :forbidden
    assert_equal I18n.t("take.errors.other_device"), @other.response.parsed_body["error"]

    @other.post student_submit_path(token: @token), params: { attempt_id: attempt.id }
    @other.assert_redirected_to student_portal_path(token: @token)

    @other.post student_focus_events_path(token: @token), params: { attempt_id: attempt.id }, as: :json
    @other.assert_response :forbidden

    attempt.reload
    assert attempt.in_progress?
    assert_empty attempt.answers
    assert_equal 0, attempt.focus_loss_count
    assert_equal 1, @assignment.attempts.count
  end

  test "the binding outlives the attempt, so another browser cannot use the next one" do
    attempt = start_in(@owner)
    @owner.post student_submit_path(token: @token), params: { attempt_id: attempt.id }
    assert attempt.reload.submitted?

    @other.post student_start_path(token: @token)
    @other.assert_redirected_to student_portal_path(token: @token)
    assert_equal 1, @assignment.attempts.count
  end

  test "a regenerated link goes to the next browser and cuts the old tab off" do
    attempt = start_in(@owner)
    @assignment.reload.regenerate_token!
    new_token = @assignment.access_token

    autosave_in(@owner, attempt)
    @owner.assert_response :not_found

    @other.post student_start_path(token: new_token)
    @other.assert_redirected_to student_run_path(token: new_token)
    assert_equal attempt, @assignment.attempts.in_progress.sole
  end

  test "an attempt begun before binding existed goes to the first browser that continues it" do
    attempt = AttemptLifecycle.start!(@assignment)

    autosave_in(@owner, attempt)
    @owner.assert_response :success

    @other.get student_run_path(token: @token)
    @other.assert_redirected_to student_portal_path(token: @token)
  end
end
